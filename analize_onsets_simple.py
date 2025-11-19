#!/usr/bin/env python3
"""
Analizzatore onset per DJ Ambisonics
"""

from pythonosc.dispatcher import Dispatcher
from pythonosc import osc_server, udp_client
import librosa
import os
import numpy as np
from scipy.signal import butter, sosfilt
import time

# Configurazione OSC
SC_HOST = "127.0.0.1"
SC_PORT = 57120
LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 57123

# Configurazione analisi audio
VALID_EXTENSIONS = {".wav", ".wave", ".aif", ".aiff", ".mp3", ".flac", ".ogg", ".m4a"}
HOP_LENGTH = 512
CHUNK_SIZE = 128  # Per invio dati in chunk

# Client OSC per SuperCollider
client = udp_client.SimpleUDPClient(SC_HOST, SC_PORT)

def calculate_bpm(file_path):
    """Calcola il BPM di un file audio."""
    try:
        # Carica l'intero file audio
        y, sr = librosa.load(file_path, sr=None, mono=True)
        
        if len(y) == 0:
            return 0.0, "File audio vuoto", None, None, None
        
        # Normalizza l'audio
        if np.abs(y).max() > 0:
            y = librosa.util.normalize(y)
        
        # Calcola BPM usando librosa
        tempo, beat_frames = librosa.beat.beat_track(
            y=y, 
            sr=sr, 
            hop_length=HOP_LENGTH,
            trim=False
        )
        
        bpm = float(tempo) if np.isfinite(tempo) and tempo > 0 else 0.0
        
        if bpm > 0:
            return bpm, f"BPM: {bpm:.1f}, beats: {len(beat_frames)}", y, sr, beat_frames
        else:
            return 0.0, "BPM non rilevabile", y, sr, None
            
    except Exception as e:
        return 0.0, f"Errore: {str(e)}", None, None, None

def calculate_envelope_features(y, sr, onset_frames):
    """
    Calcola le caratteristiche dell'envelope per ogni onset:
    Approccio ottimizzato:
    1. Converti in mono (già fatto)
    2. Filtro passa-banda 50Hz - 8kHz (elimina sub e fruscio)
    3. Rettifica (abs)
    4. Liscia con low-pass a 15Hz
    5. Calcola attacco e release
    6. Calcola valore combinato con peso maggiore sulla release
    7. Calcola frequenza spettrale media
    """
    if len(onset_frames) == 0:
        return []
    
    # Step 1: Filtro passa-banda (50Hz - 8kHz)
    nyquist = sr / 2
    low_cutoff = 50.0 / nyquist
    high_cutoff = 8000.0 / nyquist
    
    # Assicura che i cutoff siano validi (< 1.0)
    low_cutoff = min(low_cutoff, 0.99)
    high_cutoff = min(high_cutoff, 0.99)
    
    # Filtro passa-banda (Butterworth 4° ordine)
    sos_band = butter(4, [low_cutoff, high_cutoff], btype='band', output='sos')
    y_filtered = sosfilt(sos_band, y)
    
    # Step 2: Rettifica il segnale (valore assoluto)
    y_rect = np.abs(y_filtered)
    
    # Step 3: Low-pass filter (Butterworth, cutoff a 15Hz per envelope lento)
    cutoff = 15.0 / nyquist
    sos = butter(4, cutoff, btype='low', output='sos')
    envelope = sosfilt(sos, y_rect)
    
    # Normalizza envelope
    if envelope.max() > 0:
        envelope = envelope / envelope.max()
    
    # Calcola STFT per analisi spettrale (sul segnale filtrato)
    n_fft = 2048
    hop_length = 512
    S = np.abs(librosa.stft(y_filtered, n_fft=n_fft, hop_length=hop_length))
    freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
    
    features = []
    
    for i, onset_sample in enumerate(onset_frames):
        # Definisci la finestra di analisi (fino al prossimo onset o 500ms)
        max_analysis_samples = int(0.5 * sr)  # 500ms
        
        if i < len(onset_frames) - 1:
            next_onset = onset_frames[i + 1]
            window_end = min(onset_sample + max_analysis_samples, next_onset)
        else:
            window_end = min(onset_sample + max_analysis_samples, len(envelope))
        
        if window_end <= onset_sample:
            features.append({
                'attack_time': 0.0,
                'release_time': 0.0,
                'velocity_value': 0.0,
                'spectral_mean_freq': 0.0
            })
            continue
        
        # Estrai finestra envelope
        env_window = envelope[onset_sample:window_end]
        
        # Step 5: Calcola frequenza spettrale media per questa finestra
        # Converti onset_sample in frame STFT
        onset_frame = int(onset_sample / hop_length)
        window_end_frame = int(window_end / hop_length)
        
        if onset_frame >= S.shape[1]:
            onset_frame = S.shape[1] - 1
        if window_end_frame > S.shape[1]:
            window_end_frame = S.shape[1]
        
        if window_end_frame <= onset_frame:
            window_end_frame = onset_frame + 1
        
        # Estrai lo spettro nella finestra
        spectrum_window = S[:, onset_frame:window_end_frame]
        
        # Calcola la media spettrale pesata (centroid per ogni frame, poi media)
        if spectrum_window.shape[1] > 0:
            spectral_centroids = []
            for frame_idx in range(spectrum_window.shape[1]):
                frame_spectrum = spectrum_window[:, frame_idx]
                if frame_spectrum.sum() > 0:
                    # Frequenza media pesata per ampiezza
                    spectral_centroid = np.sum(freqs * frame_spectrum) / np.sum(frame_spectrum)
                    spectral_centroids.append(spectral_centroid)
            
            if spectral_centroids:
                spectral_mean_freq = np.mean(spectral_centroids)
            else:
                spectral_mean_freq = 0.0
        else:
            spectral_mean_freq = 0.0
        
        if len(env_window) < 2:
            features.append({
                'attack_time': 0.0,
                'release_time': 0.0,
                'velocity_value': 0.0,
                'spectral_mean_freq': spectral_mean_freq
            })
            continue
        
        # Step 3a: Calcola tempo di attacco (onset -> picco)
        peak_idx = np.argmax(env_window)
        attack_samples = peak_idx
        attack_time = attack_samples / sr  # in secondi
        
        # Step 3b: Calcola tempo di release (picco -> 50% del picco)
        peak_value = env_window[peak_idx]
        threshold = peak_value * 0.5
        
        # Cerca il punto dove l'envelope scende sotto la soglia
        release_samples = 0
        for j in range(peak_idx, len(env_window)):
            if env_window[j] < threshold:
                release_samples = j - peak_idx
                break
        
        if release_samples == 0:  # Non ha raggiunto la soglia
            release_samples = len(env_window) - peak_idx
        
        release_time = release_samples / sr  # in secondi
        
        # Step 4: Calcola valore combinato
        # Normalizza attack e release in [0, 1] dove 0 = veloce, 1 = lento
        # Attack veloce: < 10ms, lento: > 100ms
        attack_norm = np.clip(attack_time / 0.1, 0.0, 1.0)
        # Release veloce: < 50ms, lento: > 500ms
        release_norm = np.clip(release_time / 0.5, 0.0, 1.0)
        
        # Velocity value: 1.0 se entrambi veloci (percussivo), 0.0 se entrambi lenti (pad)
        # Formula: 1.0 - weighted average con peso maggiore sulla release (70% release, 30% attack)
        velocity_value = 1.0 - (0.3 * attack_norm + 0.7 * release_norm)
        
        features.append({
            'attack_time': attack_time,
            'release_time': release_time,
            'velocity_value': velocity_value,
            'spectral_mean_freq': spectral_mean_freq
        })
    
    print(f"[DEBUG] Features calcolate per {len(features)} onset")
    return features

def group_by_beat_position(onset_times, beat_frames, sr, features):
    """
    Raggruppa gli onset per posizione in beat.
    Tutti gli onset nella stessa zona (stesso beat) hanno lo stesso valore.
    """
    if len(onset_times) == 0:
        return []
    
    # Se non abbiamo beat_frames, crea dati senza raggruppamento beat
    if beat_frames is None or len(beat_frames) == 0:
        grouped_data = []
        
        # Calcola media mobile per le frequenze spettrali
        window_size = 20
        spectral_freqs = [f['spectral_mean_freq'] for f in features]
        
        for i, onset_time in enumerate(onset_times):
            # Media mobile frequenze
            start_idx = max(0, i - window_size + 1)
            freq_window = spectral_freqs[start_idx:i+1]
            spectral_mean_freq_smoothed = np.mean(freq_window)
            
            grouped_data.append({
                'onset_time': onset_time,
                'beat_index': 0,
                'beat_position': onset_time,  # Usa il tempo come posizione
                'beat_fraction': 0.0,
                'attack_time': features[i]['attack_time'],
                'release_time': features[i]['release_time'],
                'velocity_value': features[i]['velocity_value'],
                'velocity_value_grouped': features[i]['velocity_value'],
                'spectral_mean_freq': features[i]['spectral_mean_freq'],
                'spectral_mean_freq_smoothed': spectral_mean_freq_smoothed
            })
        
        return grouped_data
    
    # Converti beat_frames in tempi
    beat_times = librosa.frames_to_time(beat_frames, sr=sr, hop_length=HOP_LENGTH)
    
    # Calcola posizione in beat per ogni onset
    beat_start = beat_times[0] if len(beat_times) > 0 else 0.0
    beat_period = 60.0 / len(beat_times) * (beat_times[-1] - beat_start) if len(beat_times) > 1 else 1.0
    
    grouped_data = []
    
    for i, onset_time in enumerate(onset_times):
        # Calcola la posizione in beat
        beat_position = (onset_time - beat_start) / beat_period if beat_period > 0 else 0.0
        
        # Trova il beat più vicino (arrotonda)
        beat_index = int(round(beat_position))
        
        # Calcola la posizione frazionaria all'interno del beat (0.0 - 1.0)
        beat_fraction = beat_position - beat_index
        
        grouped_data.append({
            'onset_time': onset_time,
            'beat_index': beat_index,
            'beat_position': beat_position,
            'beat_fraction': beat_fraction,
            'attack_time': features[i]['attack_time'],
            'release_time': features[i]['release_time'],
            'velocity_value': features[i]['velocity_value'],
            'spectral_mean_freq': features[i]['spectral_mean_freq']
        })
    
    # Raggruppa per beat_index e calcola il valore medio per ogni gruppo
    beat_groups = {}
    for data in grouped_data:
        beat_idx = data['beat_index']
        if beat_idx not in beat_groups:
            beat_groups[beat_idx] = []
        beat_groups[beat_idx].append(data)
    
    # Assegna lo stesso velocity_value a tutti gli onset nello stesso beat
    result = []
    for beat_idx, group in beat_groups.items():
        # Usa il valore massimo del gruppo (il più percussivo)
        avg_velocity = np.mean([d['velocity_value'] for d in group])
        
        for data in group:
            data['velocity_value_grouped'] = avg_velocity
            result.append(data)
    
    # Riordina per tempo
    result.sort(key=lambda x: x['onset_time'])
    
    # Calcola la media mobile delle frequenze spettrali (ultimi 20 valori)
    window_size = 20
    for i, data in enumerate(result):
        start_idx = max(0, i - window_size + 1)
        freq_window = [result[j]['spectral_mean_freq'] for j in range(start_idx, i + 1)]
        data['spectral_mean_freq_smoothed'] = np.mean(freq_window)
    
    return result

def analyze_single_file(file_path):
    """Analizza un singolo file: validazione + BPM + envelope features."""
    filename = os.path.basename(file_path)
    
    # Validazione file
    ext = os.path.splitext(file_path)[1].lower()
    if ext not in VALID_EXTENSIONS or not os.path.isfile(file_path):
        print(f"❌ File non valido: {filename}")
        return False, 0.0, []
    
    # Step 2: Calcolo BPM e caricamento audio
    bpm, bpm_msg, y, sr, beat_frames = calculate_bpm(file_path)
    send_to_supercollider("/analysis/file_bpm", filename, bpm, bpm_msg)
    
    if y is None or sr is None:
        return False, bpm, []
    
    # Step 3: Detect onset
    onset_frames = librosa.onset.onset_detect(
        y=y,
        sr=sr,
        hop_length=HOP_LENGTH,
        units='samples',
        backtrack=True
    )
    
    if len(onset_frames) == 0:
        return True, bpm, []
    
    onset_times = onset_frames / sr
    
    # Step 4: Calcola envelope features
    features = calculate_envelope_features(y, sr, onset_frames)
    
    # Step 5: Raggruppa per beat position
    if beat_frames is not None and len(beat_frames) > 0:
        grouped_data = group_by_beat_position(onset_times, beat_frames, sr, features)
    else:
        # Se non abbiamo beat, crea dati senza raggruppamento
        grouped_data = []
        for i, onset_time in enumerate(onset_times):
            grouped_data.append({
                'onset_time': onset_time,
                'beat_index': 0,
                'beat_position': 0.0,
                'beat_fraction': 0.0,
                'attack_time': features[i]['attack_time'],
                'release_time': features[i]['release_time'],
                'velocity_value': features[i]['velocity_value'],
                'velocity_value_grouped': features[i]['velocity_value'],
                'spectral_mean_freq': features[i]['spectral_mean_freq'],
                'spectral_mean_freq_smoothed': features[i]['spectral_mean_freq']
            })
    
    # Step 6: Invia dati a SuperCollider
    send_envelope_data(filename, grouped_data)
    
    return True, bpm, grouped_data

def send_envelope_data(filename, grouped_data):
    """Invia i dati degli envelope a SuperCollider in chunk."""
    if not grouped_data:
        send_to_supercollider("/analysis/onset_data", filename, 0, 0)
        return
    
    # Prepara array per invio
    onset_times = [d['onset_time'] for d in grouped_data]
    beat_positions = [d['beat_position'] for d in grouped_data]
    velocity_values = [d['velocity_value_grouped'] for d in grouped_data]
    spectral_freqs = [d['spectral_mean_freq_smoothed'] for d in grouped_data]
    
    # Applica media mobile agli ultimi 10 valori di velocity
    window_size = 10
    velocity_smoothed = []
    for i in range(len(velocity_values)):
        start_idx = max(0, i - window_size + 1)
        window = velocity_values[start_idx:i+1]
        velocity_smoothed.append(np.mean(window))
    
    # Applica mappatura esponenziale ai valori smoothed di velocity (strength)
    # Enfatizza i valori alti, rende più soft i valori bassi
    exponent = 10.0  # Controllo della curvatura esponenziale (10.0 = enfasi molto forte)
    velocity_values_exp = [v ** exponent for v in velocity_smoothed]

    if len(grouped_data) > 0:
        release_times = np.array([d.get('release_time', 0.0) for d in grouped_data], dtype=float)
        rel_min = float(release_times.min())
        rel_max = float(release_times.max())
        if rel_max > rel_min:
            onset_spread = ((release_times - rel_min) / (rel_max - rel_min)).tolist()
        else:
            onset_spread = [0.5] * len(grouped_data)
    else:
        onset_spread = []
    
    # Controllo pause: se tra un onset e il successivo passano >2s o >8 beat,
    # alza il valore dell'onset prima della pausa di 0.2 (dopo la mappatura exp, quindi non conta nella media)
    for i in range(len(onset_times) - 1):
        time_gap = onset_times[i + 1] - onset_times[i]
        beat_gap = abs(beat_positions[i + 1] - beat_positions[i])
        
        if time_gap > 2.0 or beat_gap > 8.0:
            # Boost del 0.2, ma non superare 1.0
            velocity_values_exp[i] = min(velocity_values_exp[i] + 0.2, 1.0)
    
    # Invia in chunk - USA I NOMI CHE SUPERCOLLIDER SI ASPETTA
    def send_array_chunked(path, data_array):
        num_chunks = (len(data_array) + CHUNK_SIZE - 1) // CHUNK_SIZE
        for chunk_idx in range(num_chunks):
            start_idx = chunk_idx * CHUNK_SIZE
            end_idx = min(start_idx + CHUNK_SIZE, len(data_array))
            chunk = data_array[start_idx:end_idx]
            send_to_supercollider(path, filename, chunk_idx, len(chunk), *chunk)
            time.sleep(0.001)  # Piccolo delay per evitare overflow buffer OSC
    
    send_array_chunked("/analysis/onset_times_chunk", onset_times)
    send_array_chunked("/analysis/onset_pos_chunk", beat_positions)
    send_array_chunked("/analysis/onset_strength_chunk", velocity_values_exp)  # Valori esponenziali
    send_array_chunked("/analysis/onset_spread_chunk", onset_spread)
    
    # Normalizza le frequenze spettrali per contrast (0..1)
    if len(spectral_freqs) > 0:
        min_freq = min(spectral_freqs)
        max_freq = max(spectral_freqs)
        if max_freq > min_freq:
            contrast_normalized = [(f - min_freq) / (max_freq - min_freq) for f in spectral_freqs]
        else:
            contrast_normalized = [0.5] * len(spectral_freqs)
    else:
        contrast_normalized = []
    
    send_array_chunked("/analysis/onset_contrast_chunk", contrast_normalized)
    
    print(f"✓ {len(grouped_data)} onset inviati")

def send_to_supercollider(message_path, *args):
    """Invia un messaggio OSC a SuperCollider."""
    try:
        # Converte SEMPRE la tuple *args in lista
        client.send_message(message_path, list(args))
    except Exception as e:
        print(f"❌ Errore invio {message_path}: {e}")

def handle_test_message(addr, *args):
    """Handler per messaggi di test."""
    print(f"Test ricevuto: {args}")
    send_to_supercollider("/test/response", "received", len(args))

def handle_analyze_folder(addr, *args):
    """Handler OSC che riceve richieste di analisi cartella."""
    if len(args) < 1:
        print("❌ Manca il path della cartella")
        send_to_supercollider("/analysis/error", "Manca il path della cartella")
        return
    
    folder_path = args[0]
    print(f"\n📁 Analisi cartella: {folder_path}")
    
    # Verifica che sia una cartella
    if not os.path.isdir(folder_path):
        print(f"❌ Path non è una cartella valida")
        send_to_supercollider("/analysis/error", f"Path non valido: {folder_path}")
        return
    
    # Trova tutti i file audio
    audio_files = []
    for filename in sorted(os.listdir(folder_path)):
        ext = os.path.splitext(filename)[1].lower()
        if ext in VALID_EXTENSIONS:
            audio_files.append(os.path.join(folder_path, filename))
    
    if not audio_files:
        print(f"❌ Nessun file audio trovato")
        send_to_supercollider("/analysis/error", "Nessun file audio trovato")
        return
    
    print(f"📊 {len(audio_files)} file da analizzare")
    
    # Inizio analisi batch
    send_to_supercollider("/analysis/start", len(audio_files), folder_path)
    
    valid_bpms = []
    
    # Analizza ogni file
    for i, file_path in enumerate(audio_files):
        filename = os.path.basename(file_path)
        
        send_to_supercollider("/analysis/file_start", filename, i+1, len(audio_files))
        
        # Analisi del file
        is_valid, bpm, grouped_data = analyze_single_file(file_path)
        
        if is_valid and bpm > 0:
            valid_bpms.append(bpm)
        
        send_to_supercollider("/analysis/file_end", filename)
    
    # Calcola BPM globale se abbiamo BPM validi
    if valid_bpms:
        global_bpm = np.median(valid_bpms)
        print(f"✓ BPM globale: {global_bpm:.1f}")
    else:
        global_bpm = 0.0
    
    # Fine analisi
    send_to_supercollider("/analysis/global_bpm", global_bpm, len(valid_bpms))
    send_to_supercollider("/analysis/end", len(audio_files), len(valid_bpms))
    
    print(f"✓ Analisi completata\n")

def handle_analyze_file(addr, *args):
    """Handler OSC per analizzare un singolo file."""
    if len(args) < 1:
        print("❌ Manca il path del file")
        send_to_supercollider("/analysis/error", "Manca il path del file")
        return
    
    file_path = args[0]
    filename = os.path.basename(file_path)
    
    send_to_supercollider("/analysis/file_start", filename, 1, 1)
    
    is_valid, bpm, grouped_data = analyze_single_file(file_path)
    
    send_to_supercollider("/analysis/file_end", filename)
    send_to_supercollider("/analysis/end", 1, 1 if is_valid else 0)

def main():
    """Funzione principale - avvia il server OSC."""
    print(f"🎵 Server OSC: {LISTEN_HOST}:{LISTEN_PORT}")
    print(f"📡 Target SC: {SC_HOST}:{SC_PORT}")
    
    # Configura dispatcher OSC
    dispatcher = Dispatcher()
    dispatcher.map("/analyze_folder", handle_analyze_folder)
    dispatcher.map("/analyze_file", handle_analyze_file)
    dispatcher.map("/test", handle_test_message)
    
    # Avvia server
    server = osc_server.ThreadingOSCUDPServer((LISTEN_HOST, LISTEN_PORT), dispatcher)
    print("✓ Server pronto\n")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n✓ Server fermato")

if __name__ == "__main__":
    main()