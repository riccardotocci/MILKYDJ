// MidiController_Hercules.pde
// Controller MIDI per Hercules Inpulse 200
// FILE SEPARATO (non inner class!)

import themidibus.*;

// ==================================================
// COSTANTI HERCULES INPULSE 200
// ==================================================
final int CC_CROSSFADER_H = 0;
final int CC_FILTER_H     = 2;
final int CC_VOLUME_H     = 0;
final int CC_LOW_H        = 2;
final int CC_HIGH_H       = 4;
final int CC_PITCH_H      = 8;
final int CC_JOG_ROTATE_H = 10;

final int NOTE_PLAY_H      = 7;
final int NOTE_CUE_H       = 6;
final int NOTE_SHIFT_H     = 3;
final int NOTE_SYNC_H      = 5;
final int NOTE_PAD1_H      = 0;
final int NOTE_PAD2_H      = 10;
final int NOTE_PAD3_H      = 11;
final int NOTE_PAD4_H      = 12;
final int NOTE_JOG_TOUCH_H = 53;
final int NOTE_LOAD_H = 13;  // Bottone VINYL (o altro tasto per load)
// Browser scroll knob
final int CC_BROWSE_KNOB_H = 1;  // <-- Sostituisci con il numero reale
final int NOTE_BROWSE_SELECT_H = 0;

// Canali MIDI
final int CH_CROSSFADER_H = 0; 
final int CH_DECK_1_H = 1; // Deck A
final int CH_DECK_2_H = 2; // Deck B

// ==================================================
// CLASSE CONTROLLER (PUBLIC + metodi PUBLIC)
// ==================================================
public class MidiController_Hercules {  // <-- AGGIUNGI "public" QUI
  Deck deckA, deckB;
  MixerCenterPanel center;
  FileBrowserPanel browser;
  OscBridge osc;

  MidiBus myBus;

  // Stato jog wheel
  boolean jogTouchA = false;
  boolean jogTouchB = false;
  float jogSecondsPerDetent = 0.02;

  // ==================================================
  // COSTRUTTORE (PUBLIC)
  // ==================================================
  public MidiController_Hercules(Deck a, Deck b, MixerCenterPanel c, FileBrowserPanel f, OscBridge oscBridge) {
    deckA = a;
    deckB = b;
    center = c;
    browser = f;
    osc = oscBridge;

    // Lista device disponibili
    MidiBus.list();

    // IMPORTANTE: cambia l'indice se il controller non è il device 0
    try {
      myBus = new MidiBus(this, 1, 2);
      println("[MIDI] Hercules controller inizializzato su device #1");
      
      delay(500); // Piccolo delay per stabilizzare la connessione
      illuminateController();
    } catch (Exception e) {
      println("[MIDI] Errore inizializzazione controller: " + e.getMessage());
      myBus = null;
    }
  }
  
  
  // ==================================================
  // 🆕 FUNZIONE ILLUMINAZIONE COMPLETA
  // ==================================================
  public void illuminateController() {
    if (myBus == null) {
      println("[MIDI] Controller non inizializzato — skip illuminazione");
      return;
    }
    
    println("[MIDI] ✨ ILLUMINAZIONE COMPLETA ATTIVATA ✨");
    
    // Ciclo sui 2 canali (Deck A = 1, Deck B = 2)
    for (int canale = 1; canale <= 2; canale++) {
      // Ciclo su tutte le note possibili (0-127)
      for (int nota = 0; nota < 128; nota++) {
        myBus.sendNoteOn(canale, nota, 127); // Potenza massima
        delay(5); // Piccola pausa per effetto "scia" (rimuovi per accensione istantanea)
      }
    }
    
    println("[MIDI] 🎛️ Tutti i LED accesi!");
  }
  
  // ==================================================
// HELPER: Browser scroll con knob
// ==================================================
void handleBrowserScroll(int value) {
  int delta = value - 64; // Centrato su 64 (come il jog wheel)
  if (delta == 0) return;
  
  // Scroll solo nella lista file (la più usata)
  int stepRows = (delta > 0) ? 1 : -1;
  browser.filesScroll.stepItems(stepRows);
  
  // Opzionale: aggiorna anche la selezione corrente
  int currentSel = browser.selFileIdx;
  int newSel = constrain(currentSel + stepRows, 0, browser.fileList.size() - 1);
  browser.selFileIdx = newSel;
  
  println("[MIDI Browser] Scroll: " + stepRows + " | Sel: " + newSel);
}
  
  public void rawMidi(byte[] data) {
  // Stampa tutti i messaggi MIDI grezzi
  if (data.length >= 3) {
    int status = data[0] & 0xFF;
    int channel = status & 0x0F;
    int command = (status & 0xF0) >> 4;
    int num = data[1] & 0x7F;
    int val = data[2] & 0x7F;
    
    String cmd = (command == 11) ? "CC" : (command == 9) ? "NoteOn" : (command == 8) ? "NoteOff" : "Other";
    
    println("[MIDI DEBUG] Ch:" + channel + " Cmd:" + cmd + " Num:" + num + " Val:" + val);
  }
}
  

  // ==================================================
  // CALLBACK: controllerChange (PUBLIC)
  // ==================================================
  public void controllerChange(int channel, int number, int value) {
    if (myBus == null) return;
    
    float v = constrain(value / 127.0, 0, 1);
    boolean isDeckA = (channel == CH_DECK_1_H);
    boolean isDeckB = (channel == CH_DECK_2_H);

    // Crossfader (canale 1 di solito)
    if (channel == CH_CROSSFADER_H && number == CC_CROSSFADER_H) {
      center.setCrossfader(v);
      if (osc != null) osc.crossfader(v);
      return;
    }
    
      // === BROWSER SCROLL (su entrambi i deck) ===
  if (number == CC_BROWSE_KNOB_H) {
    handleBrowserScroll(value);
    return;
  }

    // ========================================
    // Identifica deck (canale 1 = A, canale 2 = B)
    // ========================================
    Deck d = isDeckA ? deckA : (isDeckB ? deckB : null);
    if (d == null) return; // Ignora altri canali

    // Volume deck
    if (number == CC_VOLUME_H) {
      if (isDeckA) {
        center.setVolumeA(v);
        if (osc != null) osc.deckSetVolume(deckA, v);
      } else {
        center.setVolumeB(v);
        if (osc != null) osc.deckSetVolume(deckB, v);
      }
      return;
    }

    // EQ Low
    if (number == CC_LOW_H) {
      if (isDeckA) center.setFilterA(0, v);
      else center.setFilterB(0, v);
      return;
    }

    // EQ Mid (usa CC_FILTER)
    if (number == CC_FILTER_H) {
      if (isDeckA) center.setFilterA(1, v);
      else center.setFilterB(1, v);
      return;
    }

    // EQ High
    if (number == CC_HIGH_H) {
      if (isDeckA) center.setFilterA(2, v);
      else center.setFilterB(2, v);
      return;
    }

    // Pitch (tempo)
    if (number == CC_PITCH_H) {
      d.tempo.setValue(v);
      if (osc != null) osc.deckSetSpeed(d, d.getTempoFactor());
      return;
    }

    // Jog wheel rotation
    if (number == CC_JOG_ROTATE_H) {
      handleJogRotate(d, isDeckA, value);
      return;
    }
  }

  // ==================================================
  // HELPER: Gestione rotazione jog wheel
  // ==================================================
  void handleJogRotate(Deck d, boolean isDeckA, int value) {
    int delta = value - 64; // centrato su 64
    if (delta == 0) return;

    float dir = (delta > 0) ? 1.0 : -1.0;
    boolean touched = isDeckA ? jogTouchA : jogTouchB;
    float factor = touched ? 3.0 : 1.0;

    float dt = dir * jogSecondsPerDetent * factor;
    float newPos = d.playheadSec + dt;

    if (d.analysis != null) {
      newPos = constrain(newPos, 0, d.analysis.durationSec);
    } else {
      newPos = max(0, newPos);
    }

    d.seekToSeconds(newPos);
    if (osc != null) osc.deckSeek(d, d.playheadSec);
  }

  // ==================================================
  // CALLBACK: noteOn (PUBLIC)
  // ==================================================
  public void noteOn(int channel, int pitch, int velocity) {
    if (myBus == null) return;
    
    // ========================================
    // Identifica deck (canale 1 = A, canale 2 = B)
    // ========================================
    boolean isDeckA = (channel == CH_DECK_1_H);
    boolean isDeckB = (channel == CH_DECK_2_H);
    Deck d = isDeckA ? deckA : (isDeckB ? deckB : null);
    if (d == null) return; // Ignora altri canali

    // Jog touch
    if (pitch == NOTE_JOG_TOUCH_H) {
      if (isDeckA) jogTouchA = (velocity > 0);
      else jogTouchB = (velocity > 0);
      return;
    }

// Play/Pause
if (pitch == NOTE_PLAY_H) {
  // Usa SOLO il fronte di pressione: ignora il rilascio (velocity == 0)
  if (velocity == 0) {
    // Release: non facciamo nulla
    return;
  }

  // Qui sei sicuro: è una vera pressione (velocity > 0)
  boolean wasPlaying = d.playBtn.getPlaying();
  d.playBtn.setPlaying(!wasPlaying);
  d.playPause.state = d.playBtn.getPlaying();

  if (osc != null) {
    if (!wasPlaying) {
      osc.deckPlay(d);
    } else {
      osc.deckSetCue(d, d.playheadSec);
      osc.deckStop(d);
    }
  }
  return;
}
// CUE (Hercules: NoteOn 127 = press, NoteOn 0 = release)
if (pitch == NOTE_CUE_H) {
  // Release (val == 0): emula mouseReleased sul CUE
  if (velocity == 0) {
    // Se stavamo in hold, applica stessa logica di Deck.mouseReleased
    if (d.cueHolding) {
      if (!d.playWasPlayingBeforeCue && !d.playLatchedDuringCue) {
        d.playBtn.setPlaying(false);
        d.playPause.state = false;
        d.playheadSec = d.cuePointSec; // Ritorna al punto CUE (appena settato nel press)
      }
      d.cueHolding = false;

      if (d.sentCueHoldToSC && osc != null) {
        osc.deckCueHold(d, false);
      }
      d.sentCueHoldToSC = false;
    }
    return;
  }

  // Press (val > 0): emula mousePressed sul CUE
  d.cueHolding = true;
  d.playWasPlayingBeforeCue = d.playBtn.getPlaying();
  d.playLatchedDuringCue = false;

  if (!d.playWasPlayingBeforeCue) {
    // --- MODIFICA: Aggiorna CUE alla posizione corrente ---
    d.cuePointSec = d.playheadSec;
    
    if (osc != null) {
        osc.deckSetCue(d, d.cuePointSec);
        // MODIFICA FONDAMENTALE: invia ANCHE il timestamp esatto a CUE HOLD
        // Questo garantisce che SC parta ESATTAMENTE da qui, non dal vecchio cue
        osc.deckCueHold(d, true, d.cuePointSec); 
        d.sentCueHoldToSC = true;
    }
    d.playBtn.setPlaying(true);
  }
  return;
}

    // Sync
    if (pitch == NOTE_SYNC_H) {
      d.syncToPeer();
      if (osc != null) osc.deckSetSpeed(d, d.getTempoFactor());
      return;
    }

    // Pad 1: Loop IN
    if (pitch == NOTE_PAD1_H) {
      d.loopInSec = d.playheadSec;
      if (osc != null) {
        osc.deckSetLoopIn(d, d.loopInSec);
        osc.deckSetLoopEnable(d, d.loopEnabled);
      }
      return;
    }

    // Pad 2: Loop OUT
    if (pitch == NOTE_PAD2_H) {
      d.loopOutSec = d.playheadSec;
      if (d.loopInSec >= 0 && d.loopOutSec > d.loopInSec + 0.02) {
        d.loopEnabled = true;
      }
      if (osc != null) {
        osc.deckSetLoopOut(d, d.loopOutSec);
        osc.deckSetLoopEnable(d, d.loopEnabled);
      }
      return;
    }

    // Pad 3: Toggle loop
    if (pitch == NOTE_PAD3_H) {
      d.loopEnabled = !d.loopEnabled;
      if (!d.loopEnabled) {
        d.loopInSec = -1;
        d.loopOutSec = -1;
      }
      if (osc != null) osc.deckSetLoopEnable(d, d.loopEnabled);
      return;
    }

    // Pad 4: Jump to cue
    if (pitch == NOTE_PAD4_H) {
      d.seekToSeconds(d.cuePointSec);
      if (osc != null) osc.deckSeek(d, d.playheadSec);
      return;
    }
    
    // Load track da browser (DECK 1 = A)
if (pitch == NOTE_LOAD_H && isDeckA) {
  // Carica il file selezionato nel browser sul Deck A
  browser.loadSelectedToDeck(deckA);
  return;
}

// Load track DECK B (stesso NOTE, canale 2)
if (pitch == NOTE_LOAD_H && isDeckB) {
  browser.loadSelectedToDeck(deckB);
  println("[MIDI] Load richiesto per Deck B");
  return;
}

  // === BROWSER: conferma selezione con tasto ===
  if (pitch == NOTE_BROWSE_SELECT_H) {
    browser.loadSelectedToDeck(d);
    println("[MIDI Browser] File caricato su Deck " + (isDeckA ? "A" : "B"));
    return;
  }

  }

  // ==================================================
  // CALLBACK: noteOff (PUBLIC)
  // ==================================================
public void noteOff(int channel, int pitch, int velocity) {
  if (myBus == null) return;
    
  boolean isDeckA = (channel == CH_DECK_1_H);
  boolean isDeckB = (channel == CH_DECK_2_H);
  Deck d = isDeckA ? deckA : (isDeckB ? deckB : null);
  if (d == null) return; // Ignora altri canali

  // CUE release
  if (pitch == NOTE_CUE_H) {
    if (osc != null) osc.deckCueHold(d, false);
    d.cueHolding = false;
    return;
  }

  // Jog touch release
  if (pitch == NOTE_JOG_TOUCH_H) {
    if (isDeckA) jogTouchA = false;
    else jogTouchB = false;
    return;
  }

  // --- NUOVO: gestione alternativa Play su NoteOff (se il controller lo usa come toggle) ---
  if (pitch == NOTE_PLAY_H) {
    // Interpreta NoteOff come "secondo evento" -> toggla lo stato play
    boolean wasPlaying = d.playBtn.getPlaying();
    d.playBtn.setPlaying(!wasPlaying);
    d.playPause.state = d.playBtn.getPlaying();

    if (osc != null) {
      if (!wasPlaying) {
        osc.deckPlay(d);
      } else {
        osc.deckSetCue(d, d.playheadSec);
        osc.deckStop(d);
      }
    }
    return;
  }
}
  


  // ==================================================
  // CLEANUP
  // ==================================================
  public void dispose() {
    if (myBus != null) {
      myBus.stop();
      myBus = null;
    }
  }
}
