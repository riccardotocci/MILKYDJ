# 🎧 MILKY_DJ — AI-Powered Ambisonic DJ System

<div align="center">


<img width="1200" height="860" alt="Gemini_Generated_Image_z2mk9cz2mk9cz2mk" src="https://github.com/user-attachments/assets/2a1d4d7e-03da-4bac-814a-8d21bfc71c6a" />


</div>

---

**MILKY_DJ** is an experimental, next-generation DJ software that goes beyond traditional stereo mixing. It integrates **real-time stem separation**, **AI-driven audio analysis**, and **Ambisonics spatialization** to create an immersive 3D mixing experience.

The system orchestrates three distinct environments — **Processing** (GUI), **SuperCollider** (Audio Engine), and **Python** (AI Analysis) — communicating seamlessly via **OSC (Open Sound Control)**, allowing DJs to manipulate individual track stems in a fully controllable 3D sound field.

---

## 🚀 Key Features

| Feature | Description |
|---------|-------------|
| **3D Ambisonic Audio Engine** | Full 3rd Order (or more) Higher Order Ambisonics (HOA) pipeline powered by SuperCollider.  Supports Binaural decoding (headphones) and Multi-channel speaker arrays. |
| **Automatic Stem Separation** | Integration with **Demucs** (via Python) to automatically split loaded tracks into 4 stems: Drums, Bass, Vocals, and Other. |
| **Feature-Driven Spatialization** | Extracts audio features (Onsets, Spectral Flux, Spectral Contrast) using **Librosa** and **PyTorch**, then maps them to spatial parameters (Azimuth, Elevation) in real-time. |
| **Professional DJ GUI** | Built in Processing 4, featuring dual decks, waveforms, beat grids, loops, cue points, and a dedicated mixer interface. |
| **Hardware Acceleration** | Optimized for Apple Silicon (M-series) using MPS (Metal Performance Shaders) for fast torch-based analysis. |
| **Hardware Control** | Native support for MIDI controller.  |

---

## 🛠 System Architecture

MILKY_DJ follows a distributed architecture pattern:

```
┌─────────────────────────────────────────────────────────────────────┐
│                          OSC Communication                          │
├────────────────┬────────────────────────────┬───────────────────────┤
│   Processing   │       SuperCollider        │        Python         │
│   (GUI/Logic)  │      (Audio Engine)        │    (AI Analysis)      │
├────────────────┼────────────────────────────┼───────────────────────┤
│ • User Interface│ • IEM Plugin Suite (VST)  │ • Demucs Separation   │
│ • Deck Controls │ • Ambisonic Encoding      │ • Librosa Analysis    │
│ • MIDI Mapping  │ • Binaural/Speaker Decode │ • PyTorch (MPS/CUDA)  │
│ • File Browser  │ • Playback & Transport    │ • Feature Extraction  │
└────────────────┴────────────────────────────┴───────────────────────┘
```

1. **GUI & Logic (Processing 4):** Handles the user interface, deck state logic (Play/Pause/Loop/Cue), file browsing, and MIDI mapping.  Acts as the "Brain", sending control data via OSC.

2. **Audio Server (SuperCollider):** The "Heart" of the system.  Hosts the VST plugins (IEM Suite) for Ambisonic encoding/decoding, handles file playback buffers for stems, and generates LFOs/Automation based on analysis data.

3. **Analysis Backend (Python):** The "Eye".  Runs in the background, accepting file paths via OSC, performing source separation (Demucs) and feature extraction (Librosa/Torch), and returning structured JSON data to SuperCollider. 

---

## 📦 Prerequisites

To run MILKY_DJ, you need to set up the three environments. 

### 1. Processing 4

- Download and install [Processing 4](https://processing.org/download)
- Install the following libraries via the **Contribution Manager** (`Sketch > Import Library > Add Library`):
  - `oscP5` — Network communication
  - `Beads` — Audio analysis for GUI waveforms
  - `TheMidiBus` — MIDI I/O

### 2. SuperCollider

- Download and install [SuperCollider](https://supercollider.github.io/downloads)
- Install **SC3 Plugins** via the SuperCollider package manager
- **Crucial:** Install the [VSTPlugin](https://git. iem.at/pd/vstplugin/-/releases) extension
- **VST Plugins:** Install the [IEM Plug-in Suite](https://plugins.iem.at/) — specifically:
  - `StereoEncoder`
  - `BinauralDecoder`
  - `SimpleDecoder`

### 3. Python Environment (Conda)

Create an environment named `dj_ambisonics`:

```bash
# Create environment
conda create -n dj_ambisonics python=3.9
conda activate dj_ambisonics

# Install PyTorch (with MPS support for Apple Silicon)
pip install torch torchaudio

# Install audio processing libraries
pip install librosa scipy numpy soundfile demucs python-osc
```

---

## 🚀 Getting Started

### Step 1: Start the Python Backend

Open a terminal, activate your conda environment, and run the analysis server:

```bash
conda activate dj_ambisonics
python analize_onsets_simple.py
```

> **Note:** `ambisonics_automation.py` can be used for offline batch processing of stems and analysis.

### Step 2: Boot the Audio Engine

1. Open `MILKY_DJ. scd` in SuperCollider
2.  Evaluate the entire code block (`Ctrl+Enter` / `Cmd+Enter`)
3. Wait for the server to boot and plugins to load
4. You should see: `DJ3D headless + 2 Decks + Stems Loader ready`

### Step 3: Launch the GUI

1.  Open `Main.pde` in Processing
2.  Press the **Run** button (▶️)

### Step 4: Load a Track

1.  Navigate using the built-in file browser
2. Click a file to select it, then click **Analyze** to generate stems
3. Once stems are ready (green highlight), click **Load A** or **Load B**
4. The Python backend will generate stems (if not present) and analysis data
5. SuperCollider will load the stems and map them to the Ambisonic encoders

---

## 🎛 Controls

### GUI Controls

| Element | Function |
|---------|----------|
| **Decks A/B** | Click waveforms to seek.  Drag vinyl for scratching. |
| **Mixer** | Vertical faders for volume, center slider for Crossfader. |
| **Stems** | Mute/Unmute individual stems (Drums, Bass, Instruments, Vocals). |
| **Space View** | Visualize spatial placement via the Directivity panel. |
| **Waveform Toggle** | Enable/disable waveform display to save CPU.  |

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `M` | Toggle between Main and Mixer screens |
| `S` | Open Settings screen |
| `F` | Toggle fullscreen |

### MIDI Controller (Hercules Inpulse 200)

| Control | Function |
|---------|----------|
| **Play/Pause** | Toggle playback |
| **CUE** | Hold for momentary play, release to return to cue point |
| **Jog Wheels** | Scratch / Seek through track |
| **Pads 1-4** | Loop In / Loop Out / Loop Toggle / Jump to CUE |
| **EQ Knobs** | Low / Mid / High filters |
| **Volume Faders** | Per-deck volume control |
| **Crossfader** | Mix between Deck A and Deck B |

---

## 📁 Project Structure

```
MILKY_DJ/
├── Main.pde                    # Processing entry point
├── Deck_dj. pde                 # Deck logic and transport
├── OscBridge.pde               # OSC communication layer
├── MixerCenterPanel.pde        # Central mixer controls
├── FileBrowserPanel.pde        # File browser with stem detection
├── WaveformStrip_dj.pde        # Waveform visualization
├── MidiController_Hercules.pde # MIDI controller mapping
├── dj_gui.pde                  # BPM analysis (Java)
├── ...                          # Other UI components
│
├── MILKY_DJ. scd                # SuperCollider audio engine
├── ambisonics_automation.py    # Stem separation + batch analysis
├── analize_onsets_simple.py    # Real-time OSC analysis server
│
└── stems/                      # Generated stems folder
    └── <track_name>/
        ├── drums. wav
        ├── bass.wav
        ├── vocals.wav
        ├── other. wav
        └── *_analysis.json
```

---

## 🔧 Configuration

### Audio Output (SuperCollider)

Edit `MILKY_DJ.scd` to configure your audio interface:

```supercollider
// List available devices
ServerOptions.outDevices;

// Set output device
Server.default.options.outDevice_("Your Audio Interface");
Server.default.options. numOutputBusChannels = 8;  // Adjust for your setup
```

### Headphone Output

```supercollider
~phonesOut = 6;  // Starting channel for headphone output (stereo)
```

---

## 🎵 Workflow Example

1. **Prepare your track:** Place an audio file (e.g., `song.mp3`) in a folder
2. **Analyze:** Click the file in the browser and press **Analyze**
3. **Wait:** Demucs will create `stems/song/` with 4 stem files + JSON analysis
4. **Load:** Click **Load A** to load stems into Deck A
5. **Play:** Press Play or use the MIDI controller
6.  **Mix:** Load another track into Deck B and crossfade between them
7. **Spatialize:** Each stem is automatically positioned in 3D space based on its audio features

---

## 📡 OSC Protocol Reference

### GUI → SuperCollider

| Address | Arguments | Description |
|---------|-----------|-------------|
| `/dj3d/deck/load_file` | `<A\|B>` `<path>` | Load stems for a deck |
| `/dj3d/deck/play` | `<A\|B>` `[seconds]` | Start playback |
| `/dj3d/deck/stop` | `<A\|B>` | Stop playback |
| `/dj3d/deck/seek` | `<A\|B>` `<seconds>` | Seek to position |
| `/dj3d/crossfader` | `<0. 0-1.0>` | Set crossfader position |

### Python → SuperCollider

| Address | Description |
|---------|-------------|
| `/analysis/file_bpm` | BPM detection result |
| `/analysis/onset_times_chunk` | Onset time data |
| `/analysis/onset_strength_chunk` | Velocity/strength data |
| `/analysis/onset_contrast_chunk` | Spectral contrast data |

---
## DEMO

![demo_milkydj](https://github.com/user-attachments/assets/17f1c23e-67b4-4601-932c-2b3a5def406e)

---

## 🤝 Contributing

Contributions are welcome! Feel free to:

- Report bugs via GitHub Issues
- Submit feature requests
- Open Pull Requests with improvements

---

## 📄 License

This project is open-source and available under the [MIT License](LICENSE). 

---

## 🙏 Acknowledgments

- **[Demucs](https://github.com/facebookresearch/demucs)** — Meta AI's music source separation
- **[IEM Plug-in Suite](https://plugins. iem.at/)** — Ambisonic VST plugins
- **[SuperCollider](https://supercollider. github.io/)** — Audio synthesis platform
- **[Processing](https://processing. org/)** — Creative coding environment
- **[Librosa](https://librosa.org/)** — Audio analysis library

---

<div align="center">

**Developed with ❤️ by [Riccardo Tocci](https://github. com/riccardotocci)**

*Powered by open-source audio technologies*

</div>
