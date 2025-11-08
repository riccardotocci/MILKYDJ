#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ambisonics_automation.py

Workflow locale UNICO per MILKY_DJ:
  Dato un file audio di input:
    /Users/Riccardo/Scrivania/ciccio/song.mp3
  crea stems e JSON dentro:
    /Users/Riccardo/Scrivania/ciccio/stems/song/
    ├── vocals.wav
    ├── drums.wav
    ├── bass.wav
    ├── other.wav
    ├── vocals_analysis.json
    ├── drums_analysis.json
    ├── bass_analysis.json
    ├── other_analysis.json

Caratteristiche:
- Separazione 4 stems con Demucs (modello htdemucs).
- Analisi onset + features (BPM, onset_strength, contrast, spread) per ogni stem.
- Cache dei risultati di analisi (.onset_cache/) per evitare ricalcoli.
- Opzioni CLI semplici (separazione + analisi è il comportamento di default).
- Nessun output disperse: tutto dentro la cartella stems/<basename>/.
- Se la cartella esiste e contiene già le stems, per default NON rigenera (usa --force).
- Analisi-only su intera cartella stems o su singolo file stem.
- Tutti i JSON finiscono nella stessa cartella delle stems.

Uso rapido:
    # Workflow completo (separa + analizza)
    python ambisonics_automation.py /path/to/song.mp3

    # Solo separazione
    python ambisonics_automation.py /path/to/song.mp3 --no-analyze

    # Solo analisi su cartella stems
    python ambisonics_automation.py --analyze-only --folder /path/to/stems/song/

    # Solo analisi su singolo stem
    python ambisonics_automation.py --analyze-only --file /path/to/stems/song/drums.wav

    # Forza nuova separazione (ignora stems esistenti)
    python ambisonics_automation.py /path/to/song.mp3 --force

    # Pulisci cache
    python ambisonics_automation.py --clear-cache

Note:
- Richiede Demucs installato nell'env (es. /opt/anaconda3/envs/dj_ambisonics/bin/demucs).
- Richiede: librosa, numpy, scipy (per analisi).
"""

import os
import sys
import argparse
import subprocess
import shutil
import platform
import logging
import time
import hashlib
import json
import warnings
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import lru_cache

warnings.filterwarnings('ignore')

# ---------------------------------------
# LOGGING
# ---------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
log = logging.getLogger("ambisonics")

# ---------------------------------------
# COSTANTI GENERALI
# ---------------------------------------
VALID_EXTENSIONS = {".wav", ".wave", ".aif", ".aiff", ".mp3", ".flac", ".ogg", ".m4a"}
STEM_NAMES = ["vocals", "drums", "bass", "other"]

CACHE_DIR = ".onset_cache"
MAX_WORKERS = 4
HOP_LENGTH = 512

# ---------------------------------------
# FUNZIONI UTILI PATH
# ---------------------------------------
def safe_path(p: Path) -> Path:
    return p.expanduser().resolve()

def stems_dir_for_input(input_file: str) -> Path:
    p = safe_path(Path(input_file))
    return p.parent / "stems" / p.stem

def ensure_dir(p: Path):
    p.mkdir(parents=True, exist_ok=True)

# ---------------------------------------
# DEMUCS RILEVAMENTO
# ---------------------------------------
def find_demucs():
    # 1) PATH
    cmd = shutil.which("demucs")
    if cmd:
        return cmd
    # 2) location comuni
    candidates = [
        os.path.join(os.path.dirname(sys.executable), "demucs"),
        "/opt/anaconda3/envs/dj_ambisonics/bin/demucs",
        "/opt/miniconda3/envs/dj_ambisonics/bin/demucs",
        os.path.expanduser("~/anaconda3/envs/dj_ambisonics/bin/demucs"),
        os.path.expanduser("~/miniconda3/envs/dj_ambisonics/bin/demucs"),
    ]
    for c in candidates:
        if os.path.isfile(c) and os.access(c, os.X_OK):
            log.info(f"Demucs trovato: {c}")
            return c
    log.warning("Demucs non trovato esplicitamente — uso 'demucs' (PATH)")
    return "demucs"

def auto_device():
    sysname = platform.system()
    proc = platform.processor()
    if sysname == "Darwin" and "arm" in proc.lower():
        try:
            import torch
            if torch.backends.mps.is_available():
                torch.set_float32_matmul_precision('high')
                log.info("Ottimizzazioni MPS attivate")
                return "mps"
        except Exception:
            pass
        return "mps"
    elif sysname == "Darwin":
        return "cpu"
    else:
        try:
            import torch
            if torch.cuda.is_available():
                return "cuda"
        except Exception:
            pass
        return "cpu"

# ---------------------------------------
# SEPARAZIONE STEMS
# ---------------------------------------
def separate_4stems(input_file: str, force=False, device=None) -> dict:
    """
    Separa in 4 stems se non già presenti (o se force=True).
    Ritorna dict stem->path.
    """
    t0 = time.time()
    src = safe_path(Path(input_file))
    if not src.exists():
        raise FileNotFoundError(f"File non trovato: {src}")

    out_dir = stems_dir_for_input(str(src))
    ensure_dir(out_dir)

    # Se tutte le stems esistono e non forzi, salta
    existing = all((out_dir / f"{stem}.wav").exists() for stem in STEM_NAMES)
    if existing and not force:
        log.info("Stems già presenti — salto separazione (usa --force per rigenerare).")
        return {s: str(out_dir / f"{s}.wav") for s in STEM_NAMES}

    # Temp dir
    temp_dir = out_dir / "temp_demucs"
    ensure_dir(temp_dir)

    demucs_cmd = find_demucs()
    device = device or auto_device()

    cmd = [
        demucs_cmd,
        "-o", str(temp_dir),
        "-n", "htdemucs",
        "--device", device
    ]

    # Ottimizzazioni base (segment/overlap/varianti)
    if device == "mps":
        cmd += ["--segment", "7", "--overlap", "0.05", "--shifts", "1", "--jobs", "1"]
    elif device == "cuda":
        cmd += ["--segment", "7", "--overlap", "0.1", "--shifts", "1"]
    else:
        cmd += ["--segment", "6", "--overlap", "0.15", "--shifts", "1"]

    cmd.append(str(src))

    log.info("Eseguo Demucs:")
    log.info(" ".join(f'"{c}"' if " " in c else c for c in cmd))

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        log.error(result.stderr.strip())
        raise RuntimeError("Demucs fallito")

    demucs_out = temp_dir / "htdemucs" / src.stem
    paths = {}
    for stem in STEM_NAMES:
        sfile = demucs_out / f"{stem}.wav"
        if sfile.exists():
            dst = out_dir / f"{stem}.wav"
            shutil.copy2(sfile, dst)
            paths[stem] = str(dst)
            size_mb = dst.stat().st_size / (1024 * 1024)
            log.info(f"✓ {stem}.wav ({size_mb:.1f} MB)")
        else:
            log.warning(f"Stem mancante: {stem}.wav")

    shutil.rmtree(temp_dir, ignore_errors=True)
    log.info(f"Separazione completata in {time.time()-t0:.1f}s")
    return paths

# ---------------------------------------
# CACHE ANALISI
# ---------------------------------------
def file_hash(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(8192)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()

def cache_path(path: str) -> Path:
    ensure_dir(Path(CACHE_DIR))
    fn = Path(path).name
    safe = "".join(c if c.isalnum() else "_" for c in fn)
    return Path(CACHE_DIR) / f"{safe}_{file_hash(path)}.json"

def load_cache(path: str):
    cp = cache_path(path)
    if cp.exists():
        try:
            return json.loads(cp.read_text())
        except Exception:
            return None
    return None

def save_cache(path: str, data: dict):
    cp = cache_path(path)
    try:
        cp.write_text(json.dumps(data))
    except Exception as e:
        log.warning(f"Cache write error: {e}")

# ---------------------------------------
# ANALISI AUDIO
# ---------------------------------------
import numpy as np
import librosa
from scipy.signal import butter, sosfilt

@lru_cache(maxsize=8)
def band_filter(sr):
    ny = sr / 2
    low = min(50.0 / ny, 0.99)
    high = min(8000.0 / ny, 0.99)
    return butter(4, [low, high], btype="band", output="sos")

@lru_cache(maxsize=8)
def lowpass_filter(sr):
    ny = sr / 2
    cutoff = min(15.0 / ny, 0.99)
    return butter(4, cutoff, btype="low", output="sos")

def calc_bpm(path: str):
    try:
        y, sr = librosa.load(path, sr=None, mono=True)
        if y.size == 0:
            return 0.0, None, None, None
        if np.abs(y).max() > 0:
            y = librosa.util.normalize(y)
        tempo, beat_frames = librosa.beat.beat_track(
            y=y, sr=sr, hop_length=HOP_LENGTH, trim=False
        )
        bpm = float(tempo) if tempo and tempo > 0 else 0.0
        return bpm, y, sr, beat_frames
    except Exception:
        return 0.0, None, None, None

def envelope_features(y, sr, onset_samples):
    if onset_samples.size == 0:
        return []

    sos_b = band_filter(sr)
    sos_l = lowpass_filter(sr)
    y_f = sosfilt(sos_b, y)
    env = sosfilt(sos_l, np.abs(y_f))
    vmax = env.max()
    if vmax > 0:
        env /= vmax

    n_fft = 2048
    hop = 512
    S = np.abs(librosa.stft(y_f, n_fft=n_fft, hop_length=hop))
    freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
    max_win = int(0.5 * sr)

    feats = []
    for i, onset in enumerate(onset_samples):
        # finestra fino a prossimo onset o max_win
        if i < len(onset_samples) - 1:
            end = min(onset + max_win, onset_samples[i+1])
        else:
            end = min(onset + max_win, len(env))
        if end <= onset:
            feats.append(dict(attack_time=0.0,
                              release_time=0.0,
                              velocity_value=0.0,
                              spectral_mean_freq=0.0))
            continue

        w = env[onset:end]
        peak = w.argmax()
        attack = peak / sr
        peak_val = w[peak]
        thr = peak_val * 0.5
        decay = w[peak:]
        below = np.where(decay < thr)[0]
        release = (below[0]/sr) if below.size else (decay.size/sr)

        onset_f = onset // hop
        end_f = end // hop
        onset_f = min(onset_f, S.shape[1]-1)
        end_f = min(max(end_f, onset_f+1), S.shape[1])
        spec_slice = S[:, onset_f:end_f]
        if spec_slice.size == 0:
            centroid = 0.0
        else:
            slic_sum = spec_slice.sum(axis=0)
            mask = slic_sum > 0
            if mask.any():
                weighted = (freqs[:, None] * spec_slice[:, mask]).sum(axis=0)
                centroid = (weighted / slic_sum[mask]).mean()
            else:
                centroid = 0.0

        a_norm = np.clip(attack / 0.1, 0, 1)
        r_norm = np.clip(release / 0.5, 0, 1)
        velocity = 1.0 - (0.3 * a_norm + 0.7 * r_norm)

        feats.append(dict(
            attack_time=attack,
            release_time=release,
            velocity_value=velocity,
            spectral_mean_freq=centroid
        ))
    return feats

def analyze_file(path: str):
    """
    Analizza un singolo file (usa cache se disponibile).
    Ritorna: (is_valid, bpm, grouped_data(list))
    grouped_data elementi con onset_time, velocity_value ecc.
    """
    ext = Path(path).suffix.lower()
    if ext not in VALID_EXTENSIONS or not Path(path).is_file():
        return False, 0.0, []

    cached = load_cache(path)
    if cached:
        return cached['is_valid'], cached['bpm'], cached['grouped_data']

    bpm, y, sr, beat_frames = calc_bpm(path)
    if y is None:
        data = dict(is_valid=False, bpm=bpm, grouped_data=[])
        save_cache(path, data)
        return False, bpm, []

    onset_samples = librosa.onset.onset_detect(
        y=y, sr=sr, hop_length=HOP_LENGTH, units="samples", backtrack=True
    )
    onset_times = onset_samples / sr
    feats = envelope_features(y, sr, onset_samples)

    # Beat mapping semplificato
    if beat_frames is not None and beat_frames.size > 0:
        beat_times = librosa.frames_to_time(beat_frames, sr=sr, hop_length=HOP_LENGTH)
        period = np.median(np.diff(beat_times)) if beat_times.size > 1 else 1.0
        start = beat_times[0]
        positions = (onset_times - start) / period
        beat_indices = np.round(positions).astype(int)
        beat_fracs = positions - beat_indices
    else:
        positions = onset_times.copy()
        beat_indices = np.zeros_like(positions, dtype=int)
        beat_fracs = np.zeros_like(positions)

    grouped = []
    for i, t in enumerate(onset_times):
        f = feats[i]
        grouped.append(dict(
            onset_time=float(t),
            beat_index=int(beat_indices[i]),
            beat_position=float(positions[i]),
            beat_fraction=float(beat_fracs[i]),
            attack_time=float(f['attack_time']),
            release_time=float(f['release_time']),
            velocity_value=float(f['velocity_value']),
            spectral_mean_freq=float(f['spectral_mean_freq'])
        ))

    data = dict(is_valid=True, bpm=bpm, grouped_data=grouped)
    save_cache(path, data)
    return True, bpm, grouped

def prepare_json_analysis(filename: str, bpm: float, grouped: list):
    """
    Converte la lista grouped in struttura sintetica per JSON:
      onset_times, beat_positions, onset_strength (velocity^gamma), contrast, spread
    """
    if not grouped:
        return {
            'filename': filename,
            'num_onsets': 0,
            'onset_times': [],
            'beat_positions': [],
            'onset_strength': [],
            'onset_contrast': [],
            'onset_spread': []
        }

    onset_times = np.array([g['onset_time'] for g in grouped], dtype=np.float32)
    beat_positions = np.array([g['beat_position'] for g in grouped], dtype=np.float32)
    velocity = np.array([g['velocity_value'] for g in grouped], dtype=np.float32)
    spectral = np.array([g['spectral_mean_freq'] for g in grouped], dtype=np.float32)
    release = np.array([g['release_time'] for g in grouped], dtype=np.float32)

    # Smooth retroattivo
    win = 10
    v_smooth = np.zeros_like(velocity)
    for i in range(len(velocity)):
        s = max(0, i - win + 1)
        v_smooth[i] = velocity[s:i+1].mean()

    v_exp = np.power(v_smooth, 10.0)

    if onset_times.size > 1:
        gaps = np.diff(onset_times)
        beat_gaps = np.abs(np.diff(beat_positions))
        mask = (gaps > 2.0) | (beat_gaps > 8.0)
        v_exp[:-1][mask] = np.minimum(v_exp[:-1][mask] + 0.2, 1.0)

    # Contrast normalizzato
    if spectral.size > 0:
        mn, mx = spectral.min(), spectral.max()
        contrast = (spectral - mn) / (mx - mn) if mx > mn else np.full_like(spectral, 0.5)
    else:
        contrast = np.array([])

    # Spread (release time)
    if release.size > 0:
        rmn, rmx = release.min(), release.max()
        spread = (release - rmn) / (rmx - rmn) if rmx > rmn else np.full_like(release, 0.5)
    else:
        spread = np.array([])

    return {
        'filename': filename,
        'num_onsets': int(onset_times.size),
        'onset_times': onset_times.tolist(),
        'beat_positions': beat_positions.tolist(),
        'onset_strength': v_exp.tolist(),
        'onset_contrast': contrast.tolist(),
        'onset_spread': spread.tolist()
    }

def save_analysis_json(stem_path: str, bpm: float, data: dict, target_dir: Path) -> Path:
    ensure_dir(target_dir)
    base = Path(stem_path).stem
    out = target_dir / f"{base}_analysis.json"
    payload = {
        'filename': stem_path,
        'bpm': float(bpm),
        'analysis': data
    }
    out.write_text(json.dumps(payload, indent=2))
    log.info(f"JSON salvato: {out}")
    return out

# ---------------------------------------
# ANALISI CARTELLA / FILE
# ---------------------------------------
def analyze_folder(folder: str) -> list:
    """
    Analizza tutti i file audio in una cartella (solo stems generati).
    Salva ogni JSON nella cartella stessa.
    """
    dirp = safe_path(Path(folder))
    if not dirp.is_dir():
        log.error(f"Cartella non valida: {dirp}")
        return []

    # Prende solo file audio (non filtra per nome, ma se la cartella è stems contiene i 4)
    audio_files = sorted(f for f in dirp.iterdir() if f.is_file() and f.suffix.lower() in VALID_EXTENSIONS)
    if not audio_files:
        log.warning("Nessun file audio da analizzare.")
        return []

    results = []
    valid_bpms = []

    log.info(f"Analisi parallela: {len(audio_files)} file")
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        fut_map = {ex.submit(analyze_file, str(f)): f for f in audio_files}
        for fut in as_completed(fut_map):
            f = fut_map[fut]
            try:
                is_valid, bpm, grouped = fut.result()
                if is_valid and bpm > 0:
                    valid_bpms.append(bpm)
                data = prepare_json_analysis(f.name, bpm, grouped)
                save_analysis_json(str(f), bpm, data, dirp)
                log.info(f"[Analizzato] {f.name} BPM={bpm:.1f}")
                results.append(f)
            except Exception as e:
                log.error(f"Errore analisi {f.name}: {e}")

    if valid_bpms:
        gbpm = float(np.median(valid_bpms))
        log.info(f"BPM globale (mediana): {gbpm:.1f}")
    return [str(f) for f in results]

def analyze_file_to_json(path: str) -> Path | None:
    fp = safe_path(Path(path))
    if not fp.is_file():
        log.error(f"File non valido: {fp}")
        return None
    is_valid, bpm, grouped = analyze_file(str(fp))
    data = prepare_json_analysis(fp.name, bpm, grouped)
    return save_analysis_json(str(fp), bpm, data, fp.parent)

# ---------------------------------------
# CACHE UTILS
# ---------------------------------------
def clear_cache():
    p = Path(CACHE_DIR)
    if p.exists():
        shutil.rmtree(p)
        log.info("Cache pulita")
    else:
        log.info("Cache già vuota")

# ---------------------------------------
# MAIN
# ---------------------------------------
def main():
    ap = argparse.ArgumentParser(
        description="Separazione 4 stems + Analisi onset (locale, stessa cartella)",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""Esempi:
  Workflow completo:
    python ambisonics_automation.py song.mp3

  Solo separazione:
    python ambisonics_automation.py song.mp3 --no-analyze

  Forza nuova separazione (rigenera stems):
    python ambisonics_automation.py song.mp3 --force

  Solo analisi cartella stems:
    python ambisonics_automation.py --analyze-only --folder /path/stems/song/

  Solo analisi singolo stem:
    python ambisonics_automation.py --analyze-only --file /path/stems/song/drums.wav

  Pulisci cache:
    python ambisonics_automation.py --clear-cache
"""
    )
    ap.add_argument("input", nargs="?", help="File audio di input (workflow completo se presente)")
    ap.add_argument("--no-analyze", action="store_true", help="Esegui solo separazione (niente JSON)")
    ap.add_argument("--analyze-only", action="store_true", help="Salta separazione, analizza cartella o file")
    ap.add_argument("--folder", help="Cartella da analizzare (con --analyze-only)")
    ap.add_argument("--file", help="File singolo da analizzare (con --analyze-only)")
    ap.add_argument("--device", choices=["mps", "cuda", "cpu"], help="Forza device Demucs")
    ap.add_argument("--force", action="store_true", help="Rigenera stems anche se esistono")
    ap.add_argument("--clear-cache", action="store_true", help="Pulisce la cache analisi")

    args = ap.parse_args()

    # Cache
    if args.clear_cache:
        clear_cache()
        return 0

    # Modalità analisi-only
    if args.analyze_only:
        if args.folder:
            analyze_folder(args.folder)
            return 0
        if args.file:
            analyze_file_to_json(args.file)
            return 0
        log.error("Con --analyze-only specifica --folder oppure --file")
        return 1

    # Serve input file
    if not args.input:
        ap.print_help()
        return 1

    try:
        # Separazione
        log.info("="*70)
        log.info("STEP 1/2: Separazione stems")
        log.info("="*70)

        stems_paths = separate_4stems(args.input, force=args.force, device=args.device)
        stems_dir = stems_dir_for_input(args.input)
        log.info(f"Stems directory: {stems_dir}")

        if args.no_analyze:
            log.info("Separazione completata (analisi disabilitata).")
            return 0

        # Analisi
        log.info("="*70)
        log.info("STEP 2/2: Analisi stems -> JSON")
        log.info("="*70)

        analyze_folder(str(stems_dir))

        log.info("="*70)
        log.info("WORKFLOW COMPLETO")
        log.info("="*70)
        log.info(f"Cartella finale: {stems_dir}")
        for s in STEM_NAMES:
            sp = stems_paths.get(s)
            if sp:
                log.info(f"  - {Path(sp).name}")
        log.info("JSON generati nella stessa cartella.")

        return 0

    except Exception as e:
        log.error(f"Errore fatale: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())