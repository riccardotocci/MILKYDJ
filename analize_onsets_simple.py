#!/usr/bin/env python3
"""
Analizzatore onset per DJ Ambisonics - Optimized for Apple Silicon (MPS)
"""

from pythonosc.dispatcher import Dispatcher
from pythonosc import osc_server, udp_client
import librosa
import os
import numpy as np
from scipy.signal import butter, sosfilt
import time
import torch
import torchaudio
import torchaudio.functional as F
import torchaudio.transforms as T

# Configurazione Hardware
# Verifica disponibilità MPS (Metal Performance Shaders) per M1/M2/M3/M4
DEVICE = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
print(f"🚀 Hardware Acceleration: {DEVICE}")

# Configurazione OSC
SC_HOST = "127.0.0.1"
SC_PORT = 57120
LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 57123

# Configurazione analisi audio
VALID_EXTENSIONS = {".wav", ".wave", ".aif", ".aiff", ".mp3", ".flac", ".ogg", ".m4a"}
HOP_LENGTH = 512
CHUNK_SIZE = 128

client = udp_client.SimpleUDPClient(SC_HOST, SC_PORT)

def load_audio_torch(file_path):
    """Carica audio direttamente in tensori PyTorch su GPU (MPS)."""
    try:
        # Torchaudio carica (channels, frames)
        waveform, sr = torchaudio.load(file_path)
        
        # Mix to mono se stereo: media dei canali
        if waveform.shape[0] > 1:
            waveform = torch.mean(waveform, dim=0, keepdim=True)
            
        # Sposta su MPS (GPU)
        waveform = waveform.to(DEVICE)
        return waveform, sr
    except Exception as e:
        print(f"Errore caricamento Torch: {e}")
        return None, None

def get_filter_coeffs_torch(sr, low_hz, high_hz=None, btype='low'):
    """
    Calcola coefficienti SOS su CPU (scipy) e li converte in tensori GPU.
    Torchaudio.functional.sosfilt richiede coefficienti precisi.
    """
    nyquist = sr / 2
    if btype == 'band':
        low = max(low_hz / nyquist, 0.001)
        high = min(high_hz / nyquist, 0.999)
        sos = butter(4, [low, high], btype='band', output='sos')
    else:
        cutoff = min(low_hz / nyquist, 0.999)
        sos = butter(4, cutoff, btype=btype, output='sos')
    
    # Converti in tensore MPS float32
    return torch.from_numpy(sos).float().to(DEVICE)

def calculate_bpm_hybrid(file_path, waveform_gpu, sr):
    """Calcola BPM usando Librosa (CPU) ma partendo dai dati già caricati."""
    try:
        if waveform_gpu is None or waveform_gpu.shape[1] == 0:
             return 0.0, "File vuoto", None
        
        # Per beat_track di Librosa serve Numpy su CPU
        y_cpu = waveform_gpu.cpu().numpy().flatten()
        
        # Normalizza
        if np.abs(y_cpu).max() > 0:
            y_cpu = librosa.util.normalize(y_cpu)
            
        tempo, beat_frames = librosa.beat.beat_track(
            y=y_cpu, 
            sr=sr, 
            hop_length=HOP_LENGTH, 
            trim=False
        )
        
        # --- FIX: Gestione compatibilità array/scalare per Librosa ---
        if np.ndim(tempo) > 0:
            tempo = tempo.item()  # Estrae il valore scalare dall'array
            
        bpm = float(tempo) if np.isfinite(tempo) and tempo > 0 else 0.0
        return bpm, y_cpu, beat_frames
            
    except Exception as e:
        print(f"Errore BPM: {e}")
        return 0.0, None, None

def calculate_spectral_centroid_torch(waveform_filtered, sr, n_fft=2048, hop_length=512):
    """
    Calcola il centroide spettrale interamente su GPU.
    Molto più veloce di librosa.feature.spectral_centroid in loop.
    """
    # STFT su GPU
    window = torch.hann_window(n_fft).to(DEVICE)
    stft = torch.stft(waveform_filtered.squeeze(), n_fft=n_fft, hop_length=hop_length, 
                      window=window, return_complex=True)
    magnitude = torch.abs(stft) # (freq_bins, time_frames)
    
    # Frequenze per ogni bin
    freqs = torch.linspace(0, sr/2, steps=n_fft//2 + 1, device=DEVICE).unsqueeze(1) # (freq_bins, 1)
    
    # Calcolo centroide vettorializzato: sum(freq * mag) / sum(mag)
    mag_sum = torch.sum(magnitude, dim=0)
    # Evita divisione per zero
    mag_sum[mag_sum == 0] = 1e-8
    
    centroid = torch.sum(freqs * magnitude, dim=0) / mag_sum
    return centroid # (time_frames,)

def calculate_envelope_features_gpu(waveform, sr, onset_frames):
    """
    Approccio Ibrido Ottimizzato:
    - Filtri (Butterworth): CPU (Scipy) -> Più stabile e compatibile.
    - Analisi Spettrale (STFT): GPU (MPS) -> Accelerazione massiccia.
    """
    if len(onset_frames) == 0:
        return []
    
    # --- FASE 1: FILTRAGGIO (CPU - Scipy) ---
    # Spostiamo l'audio su CPU per il filtraggio rapido
    # sosfilt di scipy è in C, quindi velocissimo anche su CPU M4
    y_cpu = waveform.cpu().numpy().flatten()
    
    # 1. Filtro Passa-Banda (50Hz - 8kHz)
    nyquist = sr / 2
    low = max(50.0 / nyquist, 0.001)
    high = min(8000.0 / nyquist, 0.999)
    sos_band = butter(4, [low, high], btype='band', output='sos')
    y_filtered_cpu = sosfilt(sos_band, y_cpu)
    
    # 2. Envelope: Rettifica + Low Pass (15Hz)
    y_rect = np.abs(y_filtered_cpu)
    cutoff_env = min(15.0 / nyquist, 0.999)
    sos_low = butter(4, cutoff_env, btype='low', output='sos')
    envelope_cpu = sosfilt(sos_low, y_rect)
    
    # Normalizza envelope
    env_max = np.max(envelope_cpu)
    if env_max > 0:
        envelope_cpu = envelope_cpu / env_max

    # --- FASE 2: ANALISI SPETTRALE (GPU - PyTorch MPS) ---
    # Riportiamo solo l'audio filtrato su GPU per fare la STFT pesante
    y_filtered_gpu = torch.from_numpy(y_filtered_cpu).float().to(DEVICE)
    
    # Calcolo curva spettrale vettorializzato su GPU
    # (Questa è la parte che guadagna di più dall'accelerazione)
    spectral_curve = calculate_spectral_centroid_torch(y_filtered_gpu, sr, n_fft=2048, hop_length=512)
    
    # Riportiamo la curva spettrale su CPU per il campionamento
    spectral_curve_cpu = spectral_curve.cpu().numpy()
    
    features = []
    total_samples = len(envelope_cpu)
    max_analysis_samples = int(0.5 * sr)
    
    # --- FASE 3: ESTRAZIONE FEATURES (Logica procedurale veloce) ---
    for i, onset_sample in enumerate(onset_frames):
        # Definisci finestra temporale
        if i < len(onset_frames) - 1:
            next_onset = onset_frames[i + 1]
            window_end = min(onset_sample + max_analysis_samples, next_onset)
        else:
            window_end = min(onset_sample + max_analysis_samples, total_samples)
            
        if window_end <= onset_sample:
            features.append({'attack_time': 0.0, 'release_time': 0.0, 'velocity_value': 0.0, 'spectral_mean_freq': 0.0})
            continue

        # Slicing su array NumPy (molto veloce)
        env_window = envelope_cpu[onset_sample:window_end]
        
        # Recupero media spettrale dalla curva pre-calcolata
        start_frame = int(onset_sample / 512)
        end_frame = int(window_end / 512)
        
        # Bounds check
        start_frame = min(start_frame, len(spectral_curve_cpu)-1)
        end_frame = min(max(end_frame, start_frame + 1), len(spectral_curve_cpu))
        
        spec_slice = spectral_curve_cpu[start_frame:end_frame]
        spectral_mean_freq = float(np.mean(spec_slice)) if len(spec_slice) > 0 else 0.0
        
        if len(env_window) < 2:
            features.append({'attack_time': 0.0, 'release_time': 0.0, 'velocity_value': 0.0, 'spectral_mean_freq': spectral_mean_freq})
            continue

        # Logica Attack/Release
        peak_idx = np.argmax(env_window)
        attack_time = peak_idx / sr
        
        peak_value = env_window[peak_idx]
        threshold = peak_value * 0.5
        
        under_thresh = np.where(env_window[peak_idx:] < threshold)[0]
        
        if len(under_thresh) > 0:
            release_samples = under_thresh[0]
        else:
            release_samples = len(env_window) - peak_idx
            
        release_time = release_samples / sr
        
        # Calcolo Velocity
        attack_norm = np.clip(attack_time / 0.1, 0.0, 1.0)
        release_norm = np.clip(release_time / 0.5, 0.0, 1.0)
        velocity_value = 1.0 - (0.3 * attack_norm + 0.7 * release_norm)
        
        features.append({
            'attack_time': attack_time,
            'release_time': release_time,
            'velocity_value': velocity_value,
            'spectral_mean_freq': spectral_mean_freq
        })
        
    return features

def group_by_beat_position(onset_times, beat_frames, sr, features):
    """Raggruppa gli onset per posizione in beat (Logica CPU pura, invariata)."""
    if len(onset_times) == 0:
        return []
    
    if beat_frames is None or len(beat_frames) == 0:
        grouped_data = []
        spectral_freqs = [f['spectral_mean_freq'] for f in features]
        for i, onset_time in enumerate(onset_times):
            start_idx = max(0, i - 20 + 1)
            freq_window = spectral_freqs[start_idx:i+1]
            spectral_mean_freq_smoothed = np.mean(freq_window)
            grouped_data.append({
                'onset_time': onset_time, 'beat_index': 0, 'beat_position': onset_time, 'beat_fraction': 0.0,
                'velocity_value_grouped': features[i]['velocity_value'], 'spectral_mean_freq_smoothed': spectral_mean_freq_smoothed,
                **features[i]
            })
        return grouped_data
    
    beat_times = librosa.frames_to_time(beat_frames, sr=sr, hop_length=HOP_LENGTH)
    beat_start = beat_times[0] if len(beat_times) > 0 else 0.0
    beat_period = 60.0 / len(beat_times) * (beat_times[-1] - beat_start) if len(beat_times) > 1 else 1.0
    
    grouped_data = []
    for i, onset_time in enumerate(onset_times):
        beat_position = (onset_time - beat_start) / beat_period if beat_period > 0 else 0.0
        beat_index = int(round(beat_position))
        beat_fraction = beat_position - beat_index
        grouped_data.append({
            'onset_time': onset_time, 'beat_index': beat_index, 'beat_position': beat_position, 'beat_fraction': beat_fraction,
            **features[i]
        })
    
    # Raggruppa e media
    beat_groups = {}
    for data in grouped_data:
        beat_groups.setdefault(data['beat_index'], []).append(data)
    
    result = []
    for beat_idx, group in beat_groups.items():
        avg_velocity = np.mean([d['velocity_value'] for d in group])
        for data in group:
            data['velocity_value_grouped'] = avg_velocity
            result.append(data)
            
    result.sort(key=lambda x: x['onset_time'])
    
    # Smoothing spettrale
    for i, data in enumerate(result):
        start_idx = max(0, i - 20 + 1)
        freq_window = [result[j]['spectral_mean_freq'] for j in range(start_idx, i + 1)]
        data['spectral_mean_freq_smoothed'] = np.mean(freq_window)
    
    return result

def analyze_single_file(file_path):
    """Orchestratore analisi ottimizzata."""
    filename = os.path.basename(file_path)
    
    # 1. Caricamento su GPU (Veloce)
    waveform_gpu, sr = load_audio_torch(file_path)
    if waveform_gpu is None:
        return False, 0.0, []

    # 2. Calcolo BPM (Richiede parziale ritorno a CPU per algoritmi complessi di librosa)
    bpm, y_cpu, beat_frames = calculate_bpm_hybrid(file_path, waveform_gpu, sr)
    
    send_to_supercollider("/analysis/file_bpm", filename, bpm, f"BPM: {bpm:.1f}")
    
    if y_cpu is None:
        del waveform_gpu # Libera VRAM
        torch.mps.empty_cache()
        return False, bpm, []
    
    # 3. Onset Detect (CPU - Librosa è più accurato di semplici implementazioni torch)
    onset_frames = librosa.onset.onset_detect(
        y=y_cpu, sr=sr, hop_length=HOP_LENGTH, units='samples', backtrack=True
    )
    
    if len(onset_frames) == 0:
        del waveform_gpu
        return True, bpm, []
    
    onset_times = onset_frames / sr
    
    # 4. Calcolo Features Envelope e Spettrali (GPU MASSIVE SPEEDUP)
    # Passiamo il tensore GPU originale, non la copia numpy
    features = calculate_envelope_features_gpu(waveform_gpu, sr, onset_frames)
    
    # Pulizia memoria GPU immediata
    del waveform_gpu
    torch.mps.empty_cache()
    
    # 5. Raggruppamento (CPU leggera)
    grouped_data = group_by_beat_position(onset_times, beat_frames, sr, features)
    
    # 6. Invio OSC
    send_envelope_data(filename, grouped_data)
    
    return True, bpm, grouped_data

def send_envelope_data(filename, grouped_data):
    """Invia i dati (invariato, solo ottimizzazioni python standard)."""
    if not grouped_data:
        send_to_supercollider("/analysis/onset_data", filename, 0, 0)
        return
    
    onset_times = [d['onset_time'] for d in grouped_data]
    beat_positions = [d['beat_position'] for d in grouped_data]
    velocity_vals = [d['velocity_value_grouped'] for d in grouped_data]
    spectral_freqs = [d['spectral_mean_freq_smoothed'] for d in grouped_data]
    
    # Smoothing velocity (Python list comp veloce)
    w_size = 10
    vel_smooth = [np.mean(velocity_vals[max(0, i-w_size+1):i+1]) for i in range(len(velocity_vals))]
    vel_exp = [v ** 10.0 for v in vel_smooth] # Exponent
    
    # Onset Spread
    if len(grouped_data) > 0:
        rels = np.array([d.get('release_time', 0.0) for d in grouped_data])
        rmin, rmax = rels.min(), rels.max()
        spread = ((rels - rmin) / (rmax - rmin)).tolist() if rmax > rmin else [0.5]*len(rels)
    else:
        spread = []
        
    # Gap boost
    for i in range(len(onset_times) - 1):
        if (onset_times[i+1] - onset_times[i] > 2.0) or (abs(beat_positions[i+1] - beat_positions[i]) > 8.0):
            vel_exp[i] = min(vel_exp[i] + 0.2, 1.0)
            
    # Contrast Normalization
    if spectral_freqs:
        smin, smax = min(spectral_freqs), max(spectral_freqs)
        contrast = [(f - smin)/(smax - smin) for f in spectral_freqs] if smax > smin else [0.5]*len(spectral_freqs)
    else:
        contrast = []

    # Helper per chunk
    def send_chunk(path, arr):
        n_chunks = (len(arr) + CHUNK_SIZE - 1) // CHUNK_SIZE
        for i in range(n_chunks):
            chunk = arr[i*CHUNK_SIZE : (i+1)*CHUNK_SIZE]
            send_to_supercollider(path, filename, i, len(chunk), *chunk)
            time.sleep(0.0005) # Delay ridotto dato che M4 elabora più in fretta
            
    send_chunk("/analysis/onset_times_chunk", onset_times)
    send_chunk("/analysis/onset_pos_chunk", beat_positions)
    send_chunk("/analysis/onset_strength_chunk", vel_exp)
    send_chunk("/analysis/onset_spread_chunk", spread)
    send_chunk("/analysis/onset_contrast_chunk", contrast)
    
    print(f"✓ {len(grouped_data)} onset inviati")

def send_to_supercollider(addr, *args):
    try:
        client.send_message(addr, list(args))
    except Exception as e:
        print(f"❌ OSC Error: {e}")

# --- Handlers OSC (Struttura invariata) ---
def handle_analyze_folder(addr, *args):
    if not args: return
    folder = args[0]
    if not os.path.isdir(folder): return
    
    files = [os.path.join(folder, f) for f in sorted(os.listdir(folder)) 
             if os.path.splitext(f)[1].lower() in VALID_EXTENSIONS]
    
    if not files: return
    
    send_to_supercollider("/analysis/start", len(files), folder)
    valid_bpms = []
    
    print(f"🔥 Starting Batch Analysis on MPS Device: {DEVICE}")
    
    for i, fpath in enumerate(files):
        fname = os.path.basename(fpath)
        send_to_supercollider("/analysis/file_start", fname, i+1, len(files))
        
        # Qui si potrebbe parallelizzare ulteriormente, ma con GPU è meglio sequenziale 
        # per non saturare la VRAM se i file sono lunghi.
        ok, bpm, _ = analyze_single_file(fpath)
        
        if ok and bpm > 0: valid_bpms.append(bpm)
        send_to_supercollider("/analysis/file_end", fname)
        
    gbpm = np.median(valid_bpms) if valid_bpms else 0.0
    print(f"✓ Global BPM: {gbpm:.1f}")
    send_to_supercollider("/analysis/global_bpm", gbpm, len(valid_bpms))
    send_to_supercollider("/analysis/end", len(files), len(valid_bpms))

def handle_analyze_file(addr, *args):
    if not args: return
    fpath = args[0]
    fname = os.path.basename(fpath)
    send_to_supercollider("/analysis/file_start", fname, 1, 1)
    ok, _, _ = analyze_single_file(fpath)
    send_to_supercollider("/analysis/file_end", fname)
    send_to_supercollider("/analysis/end", 1, 1 if ok else 0)

def main():
    dispatcher = Dispatcher()
    dispatcher.map("/analyze_folder", handle_analyze_folder)
    dispatcher.map("/analyze_file", handle_analyze_file)
    
    server = osc_server.ThreadingOSCUDPServer((LISTEN_HOST, LISTEN_PORT), dispatcher)
    print(f"🎵 M4 Optimized Server: {LISTEN_HOST}:{LISTEN_PORT} -> SC: {SC_PORT}")
    print(f"⚡ Using PyTorch Device: {DEVICE}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()