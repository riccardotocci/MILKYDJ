#!/usr/bin/env python3
"""
Ambisonics Automation - Tool unificato per DJ Ambisonics

Parte 1: Separazione audio in 4 stems (vocals, drums, bass, other) con Demucs
         Salva gli stems nella cartella stems/nome_brano/

Parte 2: Analisi onset e caratteristiche audio
         Crea file JSON con tutte le caratteristiche per ogni traccia
         I file JSON possono essere caricati in SuperCollider

Utilizzo:
    # Separa stems
    python ambisonics_automation.py separate input_audio.mp3
    python ambisonics_automation.py separate input_audio.mp3 --output custom_folder
    
    # Analizza stems e crea JSON
    python ambisonics_automation.py analyze --folder stems/song_name/
    python ambisonics_automation.py analyze --file stems/song_name/drums.wav
"""

import os
import sys
import argparse
import subprocess
import shutil
import platform
import logging
import time
from pathlib import Path

# ============================================================================
# Setup logging
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


# ============================================================================
# Utilità
# ============================================================================

def get_demucs_command():
    """Trova il comando demucs (gestisce sia PATH che path assoluto)"""
    # Prova a trovare demucs nel PATH
    demucs_cmd = shutil.which('demucs')
    
    if demucs_cmd:
        return demucs_cmd
    
    # Se non trovato, prova path comuni conda
    possible_paths = [
        os.path.join(os.path.dirname(sys.executable), 'demucs'),  # Stesso dir di python
        os.path.expanduser('~/anaconda3/envs/dj_ambisonics/bin/demucs'),
        os.path.expanduser('~/miniconda3/envs/dj_ambisonics/bin/demucs'),
        '/opt/anaconda3/envs/dj_ambisonics/bin/demucs',
        '/opt/miniconda3/envs/dj_ambisonics/bin/demucs',
    ]
    
    for path in possible_paths:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            logger.info(f"📍 Demucs trovato in: {path}")
            return path
    
    # Fallback: usa 'demucs' e speriamo sia nel PATH
    logger.warning("⚠️  Demucs non trovato in path comuni, uso 'demucs' generico")
    return 'demucs'


def get_optimal_device():
    """Rileva automaticamente il device ottimale per Demucs"""
    system = platform.system()
    processor = platform.processor()
    
    if system == "Darwin" and processor == "arm":
        # Ottimizzazioni avanzate per Apple Silicon Neural Engine
        try:
            import torch
            if torch.backends.mps.is_available():
                # Abilita ottimizzazioni MPS per Neural Engine
                torch.set_float32_matmul_precision('high')
                logger.info("🧠 Ottimizzazioni avanzate Neural Engine attivate")
        except (ImportError, AttributeError):
            pass
        return "mps"  # Apple Silicon Neural Engine
    elif system == "Darwin":
        return "cpu"  # Intel Mac
    else:
        # Linux/Windows - controlla CUDA
        try:
            import torch
            if torch.cuda.is_available():
                return "cuda"
        except ImportError:
            pass
        return "cpu"


def get_song_name(input_file):
    """Estrae il nome del brano dal file"""
    return Path(input_file).stem


# ============================================================================
# Separazione con Demucs
# ============================================================================

def separate_4stems(input_file, output_dir=None, device=None):
    """
    Separa l'audio in 4 stems usando Demucs e salva i file nella cartella output.
    
    Args:
        input_file: Path al file audio di input
        output_dir: Directory di output (default: nome_brano/)
        device: Device da usare (mps/cuda/cpu, default: auto-detect)
    
    Returns:
        dict: Dictionary con i path delle 4 stems salvate
    """
    logger.info("🎵 Avvio separazione 4 stems con Demucs")
    logger.info(f"📁 File input: {input_file}")
    
    start_time = time.time()
    
    # Verifica che il file esista
    if not os.path.exists(input_file):
        raise FileNotFoundError(f"File non trovato: {input_file}")
    
    # Determina device
    device = device or get_optimal_device()
    logger.info(f"🧠 Device selezionato: {device}")
    
    # Determina output directory
    song_name = get_song_name(input_file)
    if output_dir is None:
        output_dir = song_name
    
    os.makedirs(output_dir, exist_ok=True)
    logger.info(f"📂 Output directory: {output_dir}/")
    
    # Crea directory temporanea per Demucs
    temp_dir = os.path.join(output_dir, "temp_demucs")
    os.makedirs(temp_dir, exist_ok=True)
    
    try:
        # ====================================================================
        # Esegui Demucs
        # ====================================================================
        logger.info("\n" + "="*70)
        logger.info("🔄 Esecuzione Demucs per separazione stems...")
        logger.info("="*70)
        
        # Trova comando demucs
        demucs_cmd = get_demucs_command()
        
        # Costruisci comando Demucs
        cmd = [
            demucs_cmd,
            "-o", temp_dir,        # Output directory
            "-n", "htdemucs",      # Modello da usare (compatibile con MPS)
            "--device", device,    # Device (mps/cuda/cpu)
        ]
        
        # Ottimizzazioni per device
        if device == "mps":
            # Apple Silicon: ottimizzazioni specifiche per M3/M4 Max Neural Engine
            import multiprocessing as mp
            cpu_count = mp.cpu_count()
            
            if cpu_count >= 12:  # M3 Pro/Max, M4 Pro/Max
                cmd.extend(["--segment", "7"])      # Massimo sicuro sotto limite
                cmd.extend(["--overlap", "0.05"])   # Overlap minimo per velocità
                cmd.extend(["--shifts", "1"])       # Un solo shift
                cmd.extend(["--jobs", "1"])         # Singolo job per Neural Engine
                logger.info(f"🚀 Ottimizzazioni M3/M4 Max Neural Engine attive ({cpu_count} cores)")
            else:  # M1/M2 base
                cmd.extend(["--segment", "7"])
                cmd.extend(["--overlap", "0.1"])
                cmd.extend(["--shifts", "1"])
                logger.info(f"🍎 Ottimizzazioni Apple Neural Engine standard ({cpu_count} cores)")
        elif device == "cuda":
            # NVIDIA GPU
            cmd.extend(["--segment", "7"])
            cmd.extend(["--overlap", "0.1"])
            cmd.extend(["--shifts", "1"])
            logger.info("🚀 Ottimizzazioni CUDA GPU attive")
        else:
            # CPU
            cmd.extend(["--segment", "6"])
            cmd.extend(["--overlap", "0.15"])
            cmd.extend(["--shifts", "1"])
            logger.info("⚡ Ottimizzazioni CPU attive")
        
        cmd.append(input_file)
        
        logger.info(f"💻 Comando: {' '.join(cmd)}")
        logger.info("⏳ Elaborazione in corso (potrebbe richiedere alcuni minuti)...\n")
        
        # Esegui Demucs
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            logger.error(f"❌ Demucs fallito!")
            logger.error(f"Stderr: {result.stderr}")
            raise RuntimeError(f"Demucs error: {result.stderr}")
        
        demucs_time = time.time() - start_time
        logger.info(f"✅ Demucs completato in {demucs_time:.1f}s")
        
        # ====================================================================
        # Copia stems nella directory finale
        # ====================================================================
        logger.info("\n" + "="*70)
        logger.info("📦 Organizzazione stems nella directory output...")
        logger.info("="*70)
        
        # Path dove Demucs salva i file
        demucs_output = os.path.join(temp_dir, "htdemucs", song_name)
        
        stems = ['vocals', 'drums', 'bass', 'other']
        stem_paths = {}
        
        for stem in stems:
            src_path = os.path.join(demucs_output, f"{stem}.wav")
            dst_path = os.path.join(output_dir, f"{stem}.wav")
            
            if os.path.exists(src_path):
                shutil.copy2(src_path, dst_path)
                stem_paths[stem] = dst_path
                
                # Calcola dimensione file
                size_mb = os.path.getsize(dst_path) / (1024 * 1024)
                logger.info(f"   ✓ {stem}.wav salvato ({size_mb:.1f} MB)")
            else:
                logger.warning(f"   ⚠️ {stem}.wav non trovato")
        
        # ====================================================================
        # Pulizia directory temporanea
        # ====================================================================
        logger.info("\n🧹 Pulizia directory temporanea...")
        shutil.rmtree(temp_dir)
        logger.info("   ✓ Directory temporanea rimossa")
        
        # ====================================================================
        # Report finale
        # ====================================================================
        total_time = time.time() - start_time
        
        logger.info("\n" + "="*70)
        logger.info("✅ SEPARAZIONE COMPLETATA!")
        logger.info("="*70)
        logger.info(f"⏱️  Tempo totale: {total_time:.1f}s")
        logger.info(f"📁 Directory output: {output_dir}/")
        logger.info(f"🎵 Stems generate: {len(stem_paths)}/4")
        logger.info("\nFile salvati:")
        for stem, path in stem_paths.items():
            logger.info(f"   • {stem}.wav")
        logger.info("="*70)
        
        return stem_paths
        
    except Exception as e:
        logger.error(f"❌ Errore durante la separazione: {e}")
        
        # Pulizia in caso di errore
        if os.path.exists(temp_dir):
            logger.info("🧹 Pulizia directory temporanea dopo errore...")
            shutil.rmtree(temp_dir)
        
        raise


# ============================================================================
# PARTE 2: Analisi onset e salvataggio JSON
# ============================================================================

"""
Analizzatore onset ottimizzato per DJ Ambisonics
Salva i risultati in file JSON per ogni traccia invece di inviare messaggi OSC.
Ottimizzazioni:
- Cache per file già analizzati
- Elaborazione parallela
- Operazioni vettoriali numpy ottimizzate
- Riduzione allocazioni memoria
- Batch processing migliorato
"""

import librosa
import os
import numpy as np
from scipy.signal import butter, sosfilt
import time
import hashlib
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import lru_cache
import warnings

warnings.filterwarnings('ignore')

# Configurazione analisi audio
VALID_EXTENSIONS = {".wav", ".wave", ".aif", ".aiff", ".mp3", ".flac", ".ogg", ".m4a"}
HOP_LENGTH = 512

# Cache per analisi (evita ricalcoli)
CACHE_DIR = ".onset_cache"
MAX_WORKERS = 4  # Parallelismo per analisi multi-file

# Directory output per file JSON
OUTPUT_JSON_DIR = "output"

# Pre-calcolo filtri (evita ricalcoli)
@lru_cache(maxsize=8)
def get_band_filter(sr):
    """Cache per filtro passa-banda."""
    nyquist = sr / 2
    low_cutoff = min(50.0 / nyquist, 0.99)
    high_cutoff = min(8000.0 / nyquist, 0.99)
    return butter(4, [low_cutoff, high_cutoff], btype='band', output='sos')

@lru_cache(maxsize=8)
def get_lowpass_filter(sr):
    """Cache per filtro passa-basso."""
    nyquist = sr / 2
    cutoff = 15.0 / nyquist
    return butter(4, cutoff, btype='low', output='sos')

def get_file_hash(file_path):
    """Calcola hash MD5 del file per cache."""
    hasher = hashlib.md5()
    with open(file_path, 'rb') as f:
        # Leggi solo i primi 8KB per velocità
        hasher.update(f.read(8192))
    return hasher.hexdigest()

def get_cache_path(file_path):
    """Genera path per file cache."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    file_hash = get_file_hash(file_path)
    filename = os.path.basename(file_path)
    safe_name = "".join(c if c.isalnum() else "_" for c in filename)
    return os.path.join(CACHE_DIR, f"{safe_name}_{file_hash}.json")

def load_from_cache(file_path):
    """Carica risultati dalla cache se disponibili."""
    cache_path = get_cache_path(file_path)
    if os.path.exists(cache_path):
        try:
            with open(cache_path, 'r') as f:
                return json.load(f)
        except:
            return None
    return None

def save_to_cache(file_path, data):
    """Salva risultati in cache."""
    cache_path = get_cache_path(file_path)
    try:
        with open(cache_path, 'w') as f:
            json.dump(data, f)
    except Exception as e:
        print(f"⚠️ Errore salvataggio cache: {e}")

def calculate_bpm(file_path):
    """Calcola il BPM di un file audio (ottimizzato)."""
    try:
        # Carica l'intero file audio al sample rate originale
        y, sr = librosa.load(file_path, sr=None, mono=True)
        
        if len(y) == 0:
            return 0.0, "File audio vuoto", None, None, None
        
        # Normalizza
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

def calculate_envelope_features_vectorized(y, sr, onset_frames):
    """
    Versione vettorizzata ottimizzata del calcolo envelope features.
    Riduce loop e usa operazioni numpy batch.
    """
    if len(onset_frames) == 0:
        return []
    
    # Filtri cached
    sos_band = get_band_filter(sr)
    sos_low = get_lowpass_filter(sr)
    
    # Applica filtri
    y_filtered = sosfilt(sos_band, y)
    y_rect = np.abs(y_filtered)
    envelope = sosfilt(sos_low, y_rect)
    
    # Normalizza
    env_max = envelope.max()
    if env_max > 0:
        envelope /= env_max
    
    # STFT per analisi spettrale
    n_fft = 2048
    hop_length = 512
    S = np.abs(librosa.stft(y_filtered, n_fft=n_fft, hop_length=hop_length))
    freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
    
    max_analysis_samples = int(0.5 * sr)
    features = []
    
    # Pre-calcola finestre per tutti gli onset
    onset_windows = []
    for i, onset_sample in enumerate(onset_frames):
        if i < len(onset_frames) - 1:
            window_end = min(onset_sample + max_analysis_samples, onset_frames[i + 1])
        else:
            window_end = min(onset_sample + max_analysis_samples, len(envelope))
        onset_windows.append((onset_sample, window_end))
    
    # Batch processing per finestre
    for i, (onset_sample, window_end) in enumerate(onset_windows):
        if window_end <= onset_sample:
            features.append({
                'attack_time': 0.0,
                'release_time': 0.0,
                'velocity_value': 0.0,
                'spectral_mean_freq': 0.0
            })
            continue
        
        env_window = envelope[onset_sample:window_end]
        
        # Analisi spettrale
        onset_frame = onset_sample // hop_length
        window_end_frame = window_end // hop_length
        onset_frame = min(onset_frame, S.shape[1] - 1)
        window_end_frame = min(max(window_end_frame, onset_frame + 1), S.shape[1])
        
        spectrum_window = S[:, onset_frame:window_end_frame]
        
        # Calcolo centroid vettorizzato
        if spectrum_window.shape[1] > 0:
            spectrum_sum = spectrum_window.sum(axis=0)
            mask = spectrum_sum > 0
            if mask.any():
                weighted_freqs = (freqs[:, np.newaxis] * spectrum_window[:, mask]).sum(axis=0)
                spectral_centroids = weighted_freqs / spectrum_sum[mask]
                spectral_mean_freq = spectral_centroids.mean()
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
        
        # Attack e release vettorizzati
        peak_idx = env_window.argmax()
        attack_time = peak_idx / sr
        
        peak_value = env_window[peak_idx]
        threshold = peak_value * 0.5
        
        # Trova release usando operazioni vettoriali
        decay_region = env_window[peak_idx:]
        below_threshold = np.where(decay_region < threshold)[0]
        
        if len(below_threshold) > 0:
            release_samples = below_threshold[0]
        else:
            release_samples = len(decay_region)
        
        release_time = release_samples / sr
        
        # Calcolo velocity normalizzato
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

def group_by_beat_position_vectorized(onset_times, beat_frames, sr, features):
    """Versione vettorizzata del raggruppamento per beat."""
    if len(onset_times) == 0:
        return []
    
    onset_times_arr = np.array(onset_times)
    velocity_arr = np.array([f['velocity_value'] for f in features])
    spectral_arr = np.array([f['spectral_mean_freq'] for f in features])
    
    # Media mobile corretta: solo guardando indietro (come originale)
    window_size = 20
    spectral_smoothed = np.zeros(len(spectral_arr))
    for i in range(len(spectral_arr)):
        start_idx = max(0, i - window_size + 1)
        spectral_smoothed[i] = spectral_arr[start_idx:i+1].mean()
    
    # Gestione casi senza beat
    if beat_frames is None or len(beat_frames) == 0:
        grouped_data = []
        for i in range(len(onset_times)):
            grouped_data.append({
                'onset_time': float(onset_times_arr[i]),
                'beat_index': 0,
                'beat_position': float(onset_times_arr[i]),
                'beat_fraction': 0.0,
                'attack_time': features[i]['attack_time'],
                'release_time': features[i]['release_time'],
                'velocity_value': float(velocity_arr[i]),
                'velocity_value_grouped': float(velocity_arr[i]),
                'spectral_mean_freq': float(spectral_arr[i]),
                'spectral_mean_freq_smoothed': float(spectral_smoothed[i])
            })
        return grouped_data
    
    # Calcolo beat positions vettorizzato
    beat_times = librosa.frames_to_time(beat_frames, sr=sr, hop_length=HOP_LENGTH)
    beat_start = beat_times[0] if len(beat_times) > 0 else 0.0
    beat_period = 60.0 / len(beat_times) * (beat_times[-1] - beat_start) if len(beat_times) > 1 else 1.0
    
    beat_positions = (onset_times_arr - beat_start) / beat_period if beat_period > 0 else np.zeros_like(onset_times_arr)
    beat_indices = np.round(beat_positions).astype(int)
    beat_fractions = beat_positions - beat_indices
    
    # Raggruppa per beat e calcola medie
    grouped_data = []
    beat_groups = {}
    
    for i in range(len(onset_times)):
        beat_idx = int(beat_indices[i])
        if beat_idx not in beat_groups:
            beat_groups[beat_idx] = []
        beat_groups[beat_idx].append(i)
    
    # Calcola velocity grouped
    velocity_grouped = velocity_arr.copy()
    for beat_idx, indices in beat_groups.items():
        avg_vel = velocity_arr[indices].mean()
        for i in indices:
            velocity_grouped[i] = avg_vel
    
    for i in range(len(onset_times)):
        grouped_data.append({
            'onset_time': float(onset_times_arr[i]),
            'beat_index': int(beat_indices[i]),
            'beat_position': float(beat_positions[i]),
            'beat_fraction': float(beat_fractions[i]),
            'attack_time': features[i]['attack_time'],
            'release_time': features[i]['release_time'],
            'velocity_value': float(velocity_arr[i]),
            'velocity_value_grouped': float(velocity_grouped[i]),
            'spectral_mean_freq': float(spectral_arr[i]),
            'spectral_mean_freq_smoothed': float(spectral_smoothed[i])
        })
    
    # Riordina per tempo (importante dopo il raggruppamento)
    grouped_data.sort(key=lambda x: x['onset_time'])
    
    return grouped_data

def analyze_single_file_cached(file_path):
    """Analizza file con cache."""
    filename = os.path.basename(file_path)
    
    # Validazione
    ext = os.path.splitext(file_path)[1].lower()
    if ext not in VALID_EXTENSIONS or not os.path.isfile(file_path):
        return False, 0.0, []
    
    # Controlla cache
    cached = load_from_cache(file_path)
    if cached is not None:
        print(f"💾 Cache hit: {filename}")
        return cached['is_valid'], cached['bpm'], cached['grouped_data']
    
    # Analisi completa
    bpm, bpm_msg, y, sr, beat_frames = calculate_bpm(file_path)
    
    if y is None or sr is None:
        result = {'is_valid': False, 'bpm': bpm, 'grouped_data': []}
        save_to_cache(file_path, result)
        return False, bpm, []
    
    # Detect onset
    onset_frames = librosa.onset.onset_detect(
        y=y,
        sr=sr,
        hop_length=HOP_LENGTH,
        units='samples',
        backtrack=True
    )
    
    if len(onset_frames) == 0:
        result = {'is_valid': True, 'bpm': bpm, 'grouped_data': []}
        save_to_cache(file_path, result)
        return True, bpm, []
    
    onset_times = onset_frames / sr
    
    # Features vettorizzate
    features = calculate_envelope_features_vectorized(y, sr, onset_frames)
    
    # Raggruppamento vettorizzato
    grouped_data = group_by_beat_position_vectorized(onset_times, beat_frames, sr, features)
    
    # Salva in cache
    result = {'is_valid': True, 'bpm': bpm, 'grouped_data': grouped_data}
    save_to_cache(file_path, result)
    
    return True, bpm, grouped_data

def prepare_analysis_data(filename, grouped_data):
    """Prepara i dati di analisi per essere salvati in JSON."""
    if not grouped_data:
        return {
            'filename': filename,
            'num_onsets': 0,
            'onset_times': [],
            'beat_positions': [],
            'onset_strength': [],
            'onset_contrast': [],
            'onset_spread': []
        }
    
    n = len(grouped_data)
    
    # Pre-alloca array numpy
    onset_times = np.array([d['onset_time'] for d in grouped_data], dtype=np.float32)
    beat_positions = np.array([d['beat_position'] for d in grouped_data], dtype=np.float32)
    velocity_values = np.array([d['velocity_value_grouped'] for d in grouped_data], dtype=np.float32)
    spectral_freqs = np.array([d['spectral_mean_freq_smoothed'] for d in grouped_data], dtype=np.float32)
    release_times = np.array([d['release_time'] for d in grouped_data], dtype=np.float32)
    
    # Media mobile corretta: solo guardando indietro
    window_size = 10
    velocity_smoothed = np.zeros(len(velocity_values), dtype=np.float32)
    for i in range(len(velocity_values)):
        start_idx = max(0, i - window_size + 1)
        velocity_smoothed[i] = velocity_values[start_idx:i+1].mean()
    
    # Mappatura esponenziale vettorizzata
    exponent = 10.0
    velocity_values_exp = np.power(velocity_smoothed, exponent)
    
    # Controllo pause vettorizzato
    time_gaps = np.diff(onset_times)
    beat_gaps = np.abs(np.diff(beat_positions))
    pause_mask = (time_gaps > 2.0) | (beat_gaps > 8.0)
    
    # Applica boost dove necessario
    velocity_values_exp[:-1][pause_mask] = np.minimum(
        velocity_values_exp[:-1][pause_mask] + 0.2, 
        1.0
    )
    
    # Normalizza contrast
    if spectral_freqs.size > 0:
        min_freq = spectral_freqs.min()
        max_freq = spectral_freqs.max()
        if max_freq > min_freq:
            contrast_normalized = (spectral_freqs - min_freq) / (max_freq - min_freq)
        else:
            contrast_normalized = np.full_like(spectral_freqs, 0.5)
    else:
        contrast_normalized = np.array([])
    
    # Calcola spread basato sulla release (lineare, direttamente proporzionale)
    if release_times.size > 0:
        min_release = release_times.min()
        max_release = release_times.max()
        if max_release > min_release:
            spread_normalized = (release_times - min_release) / (max_release - min_release)
        else:
            spread_normalized = np.full_like(release_times, 0.5)
    else:
        spread_normalized = np.array([])
    
    # Crea dizionario con tutti i dati
    analysis_data = {
        'filename': filename,
        'num_onsets': n,
        'onset_times': onset_times.tolist(),
        'beat_positions': beat_positions.tolist(),
        'onset_strength': velocity_values_exp.tolist(),
        'onset_contrast': contrast_normalized.tolist(),
        'onset_spread': spread_normalized.tolist()
    }
    
    print(f"✓ {n} onset preparati per JSON")
    return analysis_data

def save_analysis_to_json(filename, bpm, analysis_data, output_dir=OUTPUT_JSON_DIR):
    """Salva i dati di analisi in un file JSON."""
    os.makedirs(output_dir, exist_ok=True)
    
    # Crea nome file JSON basato sul nome del file audio
    base_name = os.path.splitext(filename)[0]
    json_filename = f"{base_name}_analysis.json"
    json_path = os.path.join(output_dir, json_filename)
    
    # Prepara il documento JSON completo
    json_data = {
        'filename': filename,
        'bpm': float(bpm),
        'analysis': analysis_data
    }
    
    # Salva il file JSON
    try:
        with open(json_path, 'w') as f:
            json.dump(json_data, f, indent=2)
        print(f"💾 JSON salvato: {json_path}")
        return json_path
    except Exception as e:
        print(f"❌ Errore salvataggio JSON: {e}")
        return None

def analyze_folder_to_json(folder_path, output_dir=OUTPUT_JSON_DIR):
    """Analizza tutti i file in una cartella e salva i risultati in JSON."""
    print(f"\n📁 Analisi parallela cartella: {folder_path}")
    
    if not os.path.isdir(folder_path):
        print(f"❌ Path non valido: {folder_path}")
        return []
    
    # Trova file audio
    audio_files = []
    for filename in sorted(os.listdir(folder_path)):
        ext = os.path.splitext(filename)[1].lower()
        if ext in VALID_EXTENSIONS:
            audio_files.append(os.path.join(folder_path, filename))
    
    if not audio_files:
        print("❌ Nessun file audio trovato")
        return []
    
    print(f"📊 {len(audio_files)} file da analizzare (parallelo, {MAX_WORKERS} worker)")
    
    valid_bpms = []
    completed = 0
    json_files = []
    
    # Elaborazione parallela con ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        # Submit tutti i task
        future_to_file = {
            executor.submit(analyze_single_file_cached, fp): fp 
            for fp in audio_files
        }
        
        # Processa risultati man mano che completano
        for future in as_completed(future_to_file):
            file_path = future_to_file[future]
            filename = os.path.basename(file_path)
            
            try:
                is_valid, bpm, grouped_data = future.result()
                completed += 1
                
                print(f"[{completed}/{len(audio_files)}] {filename} - BPM: {bpm:.1f}")
                
                if is_valid and bpm > 0:
                    valid_bpms.append(bpm)
                
                # Prepara e salva i dati in JSON
                analysis_data = prepare_analysis_data(filename, grouped_data)
                json_path = save_analysis_to_json(filename, bpm, analysis_data, output_dir)
                
                if json_path:
                    json_files.append(json_path)
                
            except Exception as e:
                print(f"❌ Errore analisi {filename}: {e}")
    
    # BPM globale
    if valid_bpms:
        global_bpm = float(np.median(valid_bpms))
        print(f"✓ BPM globale: {global_bpm:.1f}")
    else:
        global_bpm = 0.0
    
    print(f"✓ Analisi parallela completata - {len(json_files)} file JSON creati\n")
    return json_files

def analyze_file_to_json(file_path, output_dir=OUTPUT_JSON_DIR):
    """Analizza un singolo file e salva il risultato in JSON."""
    filename = os.path.basename(file_path)
    
    print(f"\n🎵 Analisi file: {filename}")
    
    is_valid, bpm, grouped_data = analyze_single_file_cached(file_path)
    
    print(f"BPM: {bpm:.1f}")
    
    # Prepara e salva i dati in JSON
    analysis_data = prepare_analysis_data(filename, grouped_data)
    json_path = save_analysis_to_json(filename, bpm, analysis_data, output_dir)
    
    if json_path:
        print(f"✓ Analisi completata\n")
        return json_path
    else:
        print(f"❌ Errore durante il salvataggio\n")
        return None

def clear_cache():
    """Pulisce la cache."""
    try:
        if os.path.exists(CACHE_DIR):
            import shutil
            shutil.rmtree(CACHE_DIR)
            print("✓ Cache pulita")
            return True
        else:
            print("⚠️ Cache già vuota")
            return False
    except Exception as e:
        print(f"❌ Errore pulizia cache: {e}")
        return False

def main():
    """Funzione principale unificata - esegue separazione + analisi insieme di default."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Tool unificato per separazione stems e analisi audio (workflow completo di default)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Esempi:
    # Workflow completo automatico (DEFAULT): separa + analizza
    python ambisonics_automation.py song.mp3
    python ambisonics_automation.py song.mp3 --output-stems custom_stems/ --output-json custom_json/
    
    # Solo separazione (senza analisi)
    python ambisonics_automation.py song.mp3 --no-analyze
    
    # Solo analisi (stems già esistenti)
    python ambisonics_automation.py --analyze-only --folder stems/song_name/
    python ambisonics_automation.py --analyze-only --file stems/song_name/drums.wav
    
    # Pulisci la cache
    python ambisonics_automation.py --clear-cache
        """
    )
    
    # Argomento principale: file audio (opzionale se si usa --analyze-only o --clear-cache)
    parser.add_argument('input', nargs='?', help='File audio da processare (separazione + analisi)')
    
    # Opzioni per separazione
    parser.add_argument('--output-stems', default=None, 
                       help='Directory output stems (default: stems/nome_brano/)')
    parser.add_argument('-d', '--device', choices=['mps', 'cuda', 'cpu'], default=None,
                       help='Device per separazione (default: auto-detect)')
    parser.add_argument('--no-analyze', action='store_true',
                       help='Solo separazione stems, senza analisi')
    
    # Opzioni per analisi
    parser.add_argument('--output-json', default=OUTPUT_JSON_DIR,
                       help=f'Directory output JSON (default: {OUTPUT_JSON_DIR})')
    parser.add_argument('--analyze-only', action='store_true',
                       help='Solo analisi, senza separazione stems')
    parser.add_argument('--folder', help='Cartella da analizzare (con --analyze-only)')
    parser.add_argument('--file', help='File singolo da analizzare (con --analyze-only)')
    
    # Utilità
    parser.add_argument('--clear-cache', action='store_true',
                       help='Pulisce la cache delle analisi')
    
    args = parser.parse_args()
    
    # Clear cache
    if args.clear_cache:
        clear_cache()
        return 0
    
    # Solo analisi
    if args.analyze_only:
        if args.folder:
            json_files = analyze_folder_to_json(args.folder, args.output_json)
            print(f"\n✅ Creati {len(json_files)} file JSON in {args.output_json}/")
            return 0
        elif args.file:
            json_path = analyze_file_to_json(args.file, args.output_json)
            if json_path:
                print(f"\n✅ File JSON creato: {json_path}")
                return 0
            else:
                return 1
        else:
            print("❌ Errore: con --analyze-only specifica --folder o --file")
            return 1
    
    # Workflow completo o solo separazione
    if not args.input:
        parser.print_help()
        return 1
    
    try:
        # STEP 1: Separazione stems
        if args.output_stems is None:
            song_name = get_song_name(args.input)
            stems_dir = os.path.join("stems", song_name)
        else:
            stems_dir = args.output_stems
        
        logger.info("\n" + "="*70)
        logger.info("🎵 STEP 1/2: SEPARAZIONE STEMS")
        logger.info("="*70)
        
        stem_paths = separate_4stems(
            args.input,
            output_dir=stems_dir,
            device=args.device
        )
        
        print("\n✅ Separazione completata!")
        print(f"📁 Stems salvati in: {stems_dir}/")
        
        # STEP 2: Analisi (se non disabilitata)
        if not args.no_analyze:
            logger.info("\n" + "="*70)
            logger.info("📊 STEP 2/2: ANALISI STEMS → JSON")
            logger.info("="*70)
            
            json_files = analyze_folder_to_json(stems_dir, args.output_json)
            
            print("\n" + "="*70)
            print("✅ WORKFLOW COMPLETO!")
            print("="*70)
            print(f"📁 Stems: {stems_dir}/")
            print(f"📄 JSON: {args.output_json}/")
            print(f"📊 File JSON creati: {len(json_files)}")
            print("\nFile JSON:")
            for json_file in json_files:
                print(f"   • {os.path.basename(json_file)}")
            print("\n💡 Carica in SuperCollider:")
            print(f'   var data = "{args.output_json}/vocals_analysis.json".parseJSONFile;')
        else:
            print(f"\n💡 Per analizzare gli stems, esegui:")
            print(f"   python ambisonics_automation.py --analyze-only --folder {stems_dir}/")
        
        return 0
        
    except Exception as e:
        logger.error(f"\n❌ Errore fatale: {e}")
        return 1

if __name__ == "__main__":
    exit(main())
