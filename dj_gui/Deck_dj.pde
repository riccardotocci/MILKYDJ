// Deck: AGGIORNATO con la correzione finale per estrarre i dati audio da Beads usando getAllFrames().

import beads.*; // <-- Assicurati che questo import ci sia

class Deck {
  AudioContext ac; // <-- Aggiunto per Beads

  String name;

  ToggleButton playPause;
  PlayStopButton playBtn;
  Slider tempo;
  Button syncBtn;
  Button loopInBtn, loopOutBtn;
  Button cueBtn;
  Button loopInLeftBtn, loopInRightBtn;
  Button loopOutLeftBtn, loopOutRightBtn;

  StemTrack[] stems = new StemTrack[4];
  String[] stemNames = {"Drums", "Bass", "Instruments", "Vocals"};

  DirectivityPanel directivity = new DirectivityPanel();

  float x, y, w, h;
  boolean isRightDock = false;
  boolean sentCueHoldToSC = false;

  float miniX, miniY, miniW, miniH;
  float diskX, diskY, diskSize;

  String trackTitle = "No Track Loaded";

  float playheadSec = 0;
  float trackLengthSec = 180;
  static final float SPEED_RANGE = 0.166f;

  TrackAnalysis analysis = null;
  boolean isAnalyzing = false;
  String analysisError = null;
  float bpmFallback = 120.0;
  // --- Nuove variabili per drag continuo vinyl e mini waveform ---
  float dragAccumulatedAngle = 0;   // accumulo angolo totale durante il drag vinyl
  float lastDragAngle = 0;          // ultimo angolo letto (vinyl)
  boolean draggingMiniWave = false;
  float dragMiniStartPlayhead = 0;
  float lastSentSeekSec = -999f;    // throttle invio /seek

  float vinylAngle = 0;
  boolean draggingVinyl = false;
  float dragStartAngle, dragStartPlayhead, dragStartVinylAngle, dragSecondsPerRotation;

  Deck peer = null;

  boolean loopEnabled = false;
  float loopInSec = -1, loopOutSec = -1;

  boolean cueHolding = false;
  boolean playWasPlayingBeforeCue = false;
  boolean playLatchedDuringCue = false;
  float cuePointSec = 0;

  float levelSmooth = 0;

  // Il costruttore ora richiede l'AudioContext di Beads
  Deck(String name, AudioContext context) {
    this.name = name;
    this.ac = context; // Salva il riferimento all'AudioContext

    playPause = new ToggleButton("Play", false);
    playBtn = new PlayStopButton(); playBtn.setPlaying(false);
    tempo = new Slider(true, 0.5); // 0.5 = centro = 0% variazione tempo.setLabels("", "", "");
    syncBtn = new Button("Sync"); loopInBtn = new Button("IN"); loopOutBtn = new Button("OUT"); cueBtn = new Button("CUE");
    loopInLeftBtn = new Button("<"); loopInRightBtn = new Button(">"); loopOutLeftBtn = new Button("<"); loopOutRightBtn = new Button(">");

    for (int i=0; i<4; i++) stems[i] = new StemTrack(stemNames[i]);
  }

  void setPeer(Deck other) { this.peer = other; }

// --- METODO loadAudioFile (versione semplificata che usa il metodo esistente) ---
void loadAudioFile(java.io.File f) {
  trackTitle = f.getName();
  analysis = null;
  analysisError = null;
  isAnalyzing = true;
  playheadSec = 0;

  loopEnabled = false;
  loopInSec = -1;
  loopOutSec = -1;
  cuePointSec = 0;

  new Thread(() -> {
    try {
      // Usa il metodo analyzeFile esistente, che legge già tutti i formati
      analysis = new BPMAnalyzer().analyzeFile(f, p -> {});
      playheadSec = 0;
      println("[BPMAnalyzer] Analisi completata. BPM: " + analysis.bpm);
    } catch (Exception ex) {
      analysis = null;
      analysisError = ex.getMessage();
      println("Errore analisi: " + ex);
      ex.printStackTrace();
    } finally {
      isAnalyzing = false;
    }
  }).start();
}

  // --- TUTTO IL RESTO DEL TUO CODICE RIMANE IDENTICO ---

  void updateLayout(float x, float y, float w, float h) {
    this.x = x; this.y = y; this.w = w; this.h = h;
    isRightDock = (x + w/2.0) > (width/2.0);

    float pad = 14;
    float headerH = 32;

    float controlsRowH = 42;
    float stemsRowH = 52;
    float bottomGap = 6;
    float bottomControlsH = controlsRowH + stemsRowH + bottomGap + 8;

    float controlsY = y + h - bottomControlsH + 8;
    float btnH = controlsRowH;

    float gap = 8;
    float btnW = 64;
    float syncW = 70;
    float ioW = 52;
    float arrowW = 24;

    float leftStart = x + pad;
    float rightEnd  = x + w - pad;

    if (!isRightDock) {
      playBtn.setBounds(leftStart, controlsY, btnW, btnH);
      cueBtn.setBounds(playBtn.x + btnW + gap, controlsY, btnW, btnH);
      syncBtn.setBounds(cueBtn.x + btnW + gap, controlsY, syncW, btnH);

      loopInLeftBtn.setBounds(syncBtn.x + syncW + gap, controlsY + (btnH-24)/2f, arrowW, 24);
      loopInBtn.setBounds(loopInLeftBtn.x + arrowW + 4, controlsY, ioW, btnH);
      loopInRightBtn.setBounds(loopInBtn.x + ioW + 4, controlsY + (btnH-24)/2f, arrowW, 24);

      loopOutLeftBtn.setBounds(loopInRightBtn.x + arrowW + gap, controlsY + (btnH-24)/2f, arrowW, 24);
      loopOutBtn.setBounds(loopOutLeftBtn.x + arrowW + 4, controlsY, ioW, btnH);
      loopOutRightBtn.setBounds(loopOutBtn.x + ioW + 4, controlsY + (btnH-24)/2f, arrowW, 24);
    } else {
      loopOutRightBtn.setBounds(rightEnd - arrowW, controlsY + (btnH-24)/2f, arrowW, 24);
      loopOutBtn.setBounds(loopOutRightBtn.x - 4 - ioW, controlsY, ioW, btnH);
      loopOutLeftBtn.setBounds(loopOutBtn.x - 4 - arrowW, controlsY + (btnH-24)/2f, arrowW, 24);

      loopInRightBtn.setBounds(loopOutLeftBtn.x - gap - arrowW, controlsY + (btnH-24)/2f, arrowW, 24);
      loopInBtn.setBounds(loopInRightBtn.x - 4 - ioW, controlsY, ioW, btnH);
      loopInLeftBtn.setBounds(loopInBtn.x - 4 - arrowW, controlsY + (btnH-24)/2f, arrowW, 24);

      syncBtn.setBounds(loopInLeftBtn.x - gap - syncW, controlsY, syncW, btnH);
      cueBtn.setBounds(syncBtn.x - gap - btnW, controlsY, btnW, btnH);
      playBtn.setBounds(cueBtn.x - gap - btnW, controlsY, btnW, btnH);
    }

    // Stems
    float stemsY = controlsY + controlsRowH + bottomGap;
    float stemsX = x + pad;
    float stemsW = w - pad*2;
    float cellGap = 8;
    float stemW = (stemsW - cellGap*3) / 4.0;
    for (int i=0; i<4; i++) {
      float sx = stemsX + i*(stemW + cellGap);
      stems[i].setBounds(sx, stemsY, stemW, stemsRowH);
    }

    // Tempo
    float tempoW = 44;
    float availHForTempo = h - headerH - pad*3 - (controlsRowH + stemsRowH + bottomGap + 8);
    float tempoH = max(120, min(160, availHForTempo));
    float tempoX = isRightDock ? (x + w - pad - tempoW) : (x + pad);
    float tempoY = y + headerH + pad;
    tempo.setBounds(tempoX, tempoY, tempoW, tempoH);

    // Area centrale: miniWave + (VINILE | DIRECTIVITY)
    float availY = y + headerH + pad;
    float availH = h - headerH - (controlsRowH + stemsRowH + bottomGap + 8) - pad*2;
    float availX, centerW;
    if (!isRightDock) { availX = tempoX + tempoW + pad; centerW = w - pad*2 - tempoW; }
    else              { availX = x + pad;               centerW = w - pad*2 - tempoW; }

    // Mini waveform compatta
    miniH = 44;
    miniX = availX;
    miniW = centerW;
    miniY = availY;

    float gapMiniDisk = 8;

    // Sotto la mini: split orizzontale
    float centerY = miniY + miniH + gapMiniDisk;
    float centerH = availH - miniH - gapMiniDisk;

    float splitGap = 6;
    float dirW = constrain(centerW * 0.62, 220, centerW * 0.70);
    float vinylW = centerW - dirW - splitGap;

    float vinX, dirX;
    if (!isRightDock) { vinX = availX; dirX = vinX + vinylW + splitGap; }
    else              { dirX = availX; vinX = dirX + dirW + splitGap; }

    float diskMax = min(vinylW, centerH);
    diskSize = max(90, diskMax * 0.95);
    diskX = vinX + (vinylW - diskSize)/2.0;
    diskY = centerY + (centerH - diskSize)/2.0;

    directivity.setBounds(dirX, centerY, dirW, centerH);
  }

  void drawControls() {
    // Header
    fill(220);
    textAlign(LEFT, CENTER);
    textSize(16);
    text(name, x + 14, y + 18);

    // Titolo + BPM base
    textSize(13);
    fill(180);
    text(trackTitle, x + 120, y + 18);
    textAlign(RIGHT, CENTER);
    float shownBPM = (analysis != null) ? analysis.bpm : bpmFallback;
    text(nf(shownBPM, 0, 1) + " BPM", x + w - 14, y + 18);
    textSize(14);

    // Mini waveform + vinile + direttività
    drawMiniWaveform();
    drawVinyl();
    directivity.draw();

    // Riga comandi bassa
    playBtn.draw();
    drawCueButton();
    syncBtn.draw(false);
    loopInLeftBtn.draw(false);
    loopInBtn.draw(false);
    loopInRightBtn.draw(false);
    loopOutLeftBtn.draw(false);
    loopOutBtn.draw(loopEnabled);
    loopOutRightBtn.draw(false);

    // Tempo verticale
    tempo.draw();

    // Stems
    for (StemTrack s : stems) s.draw();
    
    drawTempoPercent();
    

  }
  
    void drawTempoPercent() { float pct = getTempoPercent(); // -16.6 .. +16.6 
    fill(230); textAlign(CENTER, TOP); textSize(12); text(formatSpeedPercent(pct), tempo.x + tempo.w/2f,
    tempo.y - 14); textSize(14); }

  void drawCueButton() {
    boolean hover = cueBtn.contains(mouseX, mouseY);
    stroke(60); strokeWeight(1);
    if (cueHolding) fill(255, 160, 60);
    else if (cueBtn.pressed) fill(60);
    else if (hover) fill(50);
    else fill(40);
    rect(cueBtn.x, cueBtn.y, cueBtn.w, cueBtn.h, 8);

    fill(230);
    textAlign(CENTER, CENTER);
    text("CUE", cueBtn.x + cueBtn.w/2, cueBtn.y + cueBtn.h/2);
  }

float sliderToFactor(float s) {// s in [0,1] -> fattore in [1-SPEED_RANGE, 1+SPEED_RANGE] 
float f = 1.0f + (s - 0.5f) * (SPEED_RANGE * 2.0f); 
return constrain(f, 1.0f - SPEED_RANGE, 1.0f + SPEED_RANGE); }

float factorToSlider(double fIn) { float f = (float)fIn; f = constrain(f, 1.0f - SPEED_RANGE, 1.0f + SPEED_RANGE); 
return ((f - 1.0f) / (SPEED_RANGE * 2.0f)) + 0.5f; }

float getTempoFactor() { return sliderToFactor(tempo.getValue()); }
  float getEffectiveBPM() { return ((analysis != null) ? analysis.bpm : bpmFallback) * getTempoFactor(); }
  float getLevelLinear() { return constrain(levelSmooth, 0, 1); }
  
  float getTempoPercent() { return (getTempoFactor() - 1.0f) * 100.0f; }
  String formatSpeedPercent(float p) { String sgn = (p >= 0) ? "+" : ""; return sgn + nf(p, 0, 1) + "%"; }

  void updateTransport(float dt) {
    if (draggingVinyl) return;
    playPause.state = playBtn.getPlaying();

    if (playPause.state) {
      playheadSec += dt * getTempoFactor();

      if (loopEnabled && loopInSec >= 0 && loopOutSec > loopInSec) {
        if (playheadSec >= loopOutSec) playheadSec = loopInSec;
      }

      float dur = (analysis != null) ? analysis.durationSec : trackLengthSec;
      if (dur > 0 && playheadSec >= dur) playheadSec -= dur;
    }

    // Stima livello per VU
    float aNow = 0.0;
    if (analysis != null && analysis.wfMin != null && analysis.wfMax != null) {
      float idxF = playheadSec / max(1e-6, analysis.wfHopSec);
      int i0 = floor(idxF);
      int i1 = min(analysis.wfMin.length - 1, i0 + 1);
      float frac = constrain(idxF - i0, 0, 1);
      float vMin = lerp(analysis.wfMin[max(0, min(i0, analysis.wfMin.length-1))], analysis.wfMin[i1], frac);
      float vMax = lerp(analysis.wfMax[max(0, min(i0, analysis.wfMax.length-1))], analysis.wfMax[i1], frac);
      aNow = max(abs(vMin), abs(vMax));
    }
    float attack = 12.0, release = 6.0;
    float k = (aNow > levelSmooth) ? min(1, dt * attack) : min(1, dt * release);
    levelSmooth = lerp(levelSmooth, aNow, k);

    // Rotazione vinile
    float effBPM = getEffectiveBPM();
    float revPerSec = effBPM / 240.0;
    float rps = (playPause.state ? revPerSec : 0.02);
    vinylAngle += TWO_PI * rps * dt;
    if (vinylAngle > TWO_PI) vinylAngle -= TWO_PI * floor(vinylAngle / TWO_PI);
  }

  void seekToSeconds(float t) {
    float dur = (analysis != null) ? analysis.durationSec : trackLengthSec;
    playheadSec = constrain(t, 0, dur);
  }
  
  void updatePlayheadFromMini(float mx) {
    if (analysis == null) return;
    float dur = analysis.durationSec;
    float left = miniX + 6;
    float right = miniX + miniW - 6;
    float tNorm = (mx - left) / max(1, (right - left));
    float t = constrain(tNorm, 0, 1) * dur;
    seekToSeconds(t);
  }

  void syncToPeer() {
    if (peer == null) return;
    float otherEff = peer.getEffectiveBPM();
    float myBase = (analysis != null) ? analysis.bpm : bpmFallback;
    if (myBase <= 0) return;
    float targetFactor = constrain(otherEff / myBase, 0.75, 1.5);
    tempo.setValue(factorToSlider(targetFactor));

    float otherBase = (peer.analysis != null) ? peer.analysis.bpm : peer.bpmFallback;
    float periodOther = 60.0 / max(1e-4, otherBase);
    float otherBeatStart = nearestBeatStart(peer.analysis, peer.playheadSec, periodOther);
    float otherFrac = (peer.playheadSec - otherBeatStart) / periodOther;

    float myPeriod = 60.0 / myBase;
    float myBeatStart = nearestBeatStart(this.analysis, this.playheadSec, myPeriod);
    float newPos = myBeatStart + constrain(otherFrac, 0, 1) * myPeriod;
    seekToSeconds(newPos);
  }

  float nearestBeatStart(TrackAnalysis A, float t, float period) {
    if (A != null && A.beats != null && !A.beats.isEmpty()) {
      int idx = A.beatIndexAtTime(t);
      if (idx < 0) return 0;
      float bt = A.beats.get(idx);
      float next = (idx + 1 < A.beats.size()) ? A.beats.get(idx + 1) : bt + period;
      return (abs(t - next) < abs(t - bt)) ? next : bt;
    } else {
      return round(t / period) * period;
    }
  }

  boolean pointInDisk(float mx, float my) { return dist(mx, my, diskX + diskSize/2f, diskY + diskSize/2f) <= diskSize/2f; }
  float shortestAngleDiff(float a1, float a0) { return atan2(sin(a1 - a0), cos(a1 - a0)); }

  void mousePressed(float mx, float my) {
    playBtn.mousePressed(mx, my);
    tempo.mousePressed(mx, my);
    syncBtn.mousePressed(mx, my);
    loopInBtn.mousePressed(mx, my);
    loopOutBtn.mousePressed(mx, my);
    cueBtn.mousePressed(mx, my);
    loopInLeftBtn.mousePressed(mx, my); loopInRightBtn.mousePressed(mx, my);
    loopOutLeftBtn.mousePressed(mx, my); loopOutRightBtn.mousePressed(mx, my);
    directivity.mousePressed(mx, my);
    for (StemTrack s : stems) s.mousePressed(mx, my);

    // CUE momentary (come prima)
    if (cueBtn.contains(mx, my)) {
      cueHolding = true;
      playWasPlayingBeforeCue = playBtn.getPlaying();
      playLatchedDuringCue = false;
      if (!playWasPlayingBeforeCue && osc != null) {
        osc.deckCueHold(this, true);
        sentCueHoldToSC = true;
      }
      if (!playWasPlayingBeforeCue) {
        playheadSec = cuePointSec;
        playBtn.setPlaying(true);
      }
    }

    // Vinyl drag: avvio con angolo cumulativo
    if (pointInDisk(mx, my)) {
      draggingVinyl = true;
      float cx = diskX + diskSize/2f, cy = diskY + diskSize/2f;
      dragStartAngle = atan2(my - cy, mx - cx);
      lastDragAngle = dragStartAngle;
      dragAccumulatedAngle = 0;
      dragStartPlayhead = playheadSec;
      dragStartVinylAngle = vinylAngle;
      dragSecondsPerRotation = 240.0 / max(1e-4, getEffectiveBPM());
    }

    // Mini waveform drag (scrub lineare)
    if (mx >= miniX && mx <= miniX + miniW && my >= miniY && my <= miniY + miniH) {
      draggingMiniWave = true;
      dragMiniStartPlayhead = playheadSec;
      updatePlayheadFromMini(mx);
      // invia subito /seek
      if (osc != null) osc.deckSeek(this, playheadSec);
      lastSentSeekSec = playheadSec;
    }
  }

  void mouseDragged(float mx, float my) {
    tempo.mouseDragged(mx, my);
    directivity.mouseDragged(mx, my);
    for (StemTrack s : stems) s.mouseDragged(mx, my);

    // Vinyl drag continuo (multi rotazioni)
    if (draggingVinyl) {
      float cx = diskX + diskSize/2f, cy = diskY + diskSize/2f;
      float angNow = atan2(my - cy, mx - cx);
      float delta = atan2(sin(angNow - lastDragAngle), cos(angNow - lastDragAngle)); // normalizzato -PI..PI
      dragAccumulatedAngle += delta;
      lastDragAngle = angNow;

      float newT = dragStartPlayhead + (dragAccumulatedAngle / TWO_PI) * dragSecondsPerRotation;
      // clamp (nessun wrap)
      float dur = (analysis != null) ? analysis.durationSec : trackLengthSec;
      newT = constrain(newT, 0, dur);
      seekToSeconds(newT);

      // aggiorna disco grafico (angolo relativo, opzionale tenere accumulato)
      vinylAngle = dragStartVinylAngle + dragAccumulatedAngle;
      // normalizza solo per disegno (non influenza tempo)
      vinylAngle = vinylAngle % TWO_PI;

      // Throttle invio /seek ogni 50 ms di audio spostato
      if (osc != null && abs(playheadSec - lastSentSeekSec) > 0.05f) {
        osc.deckSeek(this, playheadSec);
        lastSentSeekSec = playheadSec;
      }
    }

    // Mini waveform drag
    if (draggingMiniWave) {
      updatePlayheadFromMini(mx);
      if (osc != null && abs(playheadSec - lastSentSeekSec) > 0.05f) {
        osc.deckSeek(this, playheadSec);
        lastSentSeekSec = playheadSec;
      }
    }
  }

void mouseReleased(float mx, float my) {
  boolean playBtnWasPressed = playBtn.pressed;

  playBtn.mouseReleased(mx, my);
  tempo.mouseReleased(mx, my);
  directivity.mouseReleased(mx, my);
  for (StemTrack s : stems) s.mouseReleased(mx, my);

  // Rilascio CUE (gestione hold)
  if (cueBtn.pressed && cueBtn.contains(mx, my)) {
    if (cueHolding) {
      if (!playWasPlayingBeforeCue && !playLatchedDuringCue) {
        playBtn.setPlaying(false);
        playPause.state = false;
        playheadSec = cuePointSec;
      }
      cueHolding = false;

      if (sentCueHoldToSC && osc != null) {
        osc.deckCueHold(this, false);
      }
      sentCueHoldToSC = false;
    }
  }
  cueBtn.mouseReleased(mx,my);

  // Loop IN
  if (loopInBtn.pressed && loopInBtn.contains(mx, my)) {
    loopInSec = playheadSec;
    if (loopOutSec > loopInSec) loopEnabled = true;

    if (osc != null) {
      osc.deckSetLoopIn(this, loopInSec);
      osc.deckSetLoopEnable(this, loopEnabled);
    }
  }
  loopInBtn.mouseReleased(mx,my);

  // Loop OUT / toggle enable
  if (loopOutBtn.pressed && loopOutBtn.contains(mx, my)) {
    if (!loopEnabled) {
      loopOutSec = playheadSec;
      if (loopInSec >= 0 && loopOutSec > loopInSec + 0.02f) {
        loopEnabled = true;
        if (playheadSec >= loopOutSec) playheadSec = loopInSec;
      }
    } else {
      loopEnabled = false; loopInSec = -1; loopOutSec = -1;
    }
    if (osc != null) {
      if (loopOutSec >= 0) osc.deckSetLoopOut(this, loopOutSec);
      osc.deckSetLoopEnable(this, loopEnabled);
    }
  }
  loopOutBtn.mouseReleased(mx,my);

  if (loopInLeftBtn.pressed && loopInLeftBtn.contains(mx, my)) adjustLoopPoint('I', -1);
  if (loopInRightBtn.pressed && loopInRightBtn.contains(mx, my)) adjustLoopPoint('I', +1);
  if (loopOutLeftBtn.pressed && loopOutLeftBtn.contains(mx, my)) adjustLoopPoint('O', -1);
  if (loopOutRightBtn.pressed && loopOutRightBtn.contains(mx, my)) adjustLoopPoint('O', +1);
  loopInLeftBtn.mouseReleased(mx,my); loopInRightBtn.mouseReleased(mx,my);
  loopOutLeftBtn.mouseReleased(mx,my); loopOutRightBtn.mouseReleased(mx,my);

  // Se durante il cue-hold hai premuto Play, ricordalo
  if (cueHolding && playBtnWasPressed && !playWasPlayingBeforeCue && playBtn.contains(mx, my)) {
    playLatchedDuringCue = true;
  }

  // Fine drag vinile: invia seek finale a SC
  if (draggingVinyl) {
    if (osc != null) {
      osc.deckSeek(this, playheadSec);
      lastSentSeekSec = playheadSec;
    }
  }
  draggingVinyl = false;

    // Fine drag vinyl: invia seek finale
    if (draggingVinyl) {
      if (osc != null) osc.deckSeek(this, playheadSec);
    }
    draggingVinyl = false;

    // Fine drag mini waveform
    if (draggingMiniWave) {
      if (osc != null) osc.deckSeek(this, playheadSec);
    }
    draggingMiniWave = false;

    // Play/Stop (mantieni comportamento originale)
    if (playBtnWasPressed && playBtn.contains(mx, my)) {
      if (osc != null) {
        if (playBtn.getPlaying()) osc.deckPlay(this);
        else {
          // Salva cue prima di fermare (resume)
          osc.deckSetCue(this, playheadSec);
          osc.deckStop(this);
        }
      }
    }

    // Aggiorna speed (già presente)
    if (osc != null) {
      osc.deckSetSpeed(this, getTempoFactor());
    }

  // Allinea lo stato toggle locale
  playPause.state = playBtn.getPlaying();
}

  void adjustLoopPoint(char point, int direction) {
    if (analysis == null || analysis.beats == null || analysis.beats.isEmpty()) return;
    float targetSec = (point == 'I') ? loopInSec : loopOutSec;
    if (targetSec < 0) return;
    int currentIdx = analysis.beatIndexAtTime(targetSec);
    if (currentIdx < 0) return;
    if (abs(targetSec - analysis.beats.get(currentIdx)) > 0.01 && targetSec > analysis.beats.get(currentIdx)) {
      currentIdx++;
    }
    int newIdx = constrain(currentIdx + direction, 0, analysis.beats.size() - 1);
    float newTime = analysis.beats.get(newIdx);
    if (point == 'I' && (loopOutSec < 0 || newTime < loopOutSec - 0.05)) loopInSec = newTime;
    else if (point == 'O' && newTime > loopInSec + 0.05) loopOutSec = newTime;
  }

  void drawMiniWaveform() {
    noStroke();
    fill(26);
    rect(miniX, miniY, miniW, miniH, 6);

    float left = miniX + 6, right = miniX + miniW - 6;
    float top = miniY + 6, bottom = miniY + miniH - 6;
    float cy = (top + bottom) * 0.5;

    stroke(44); strokeWeight(1);
    line(left, cy, right, cy);

    TrackAnalysis A = analysis;
    if (A == null || A.wfMin == null) {
      stroke(90, 200, 255, 120);
      line(left, cy, right, cy);
      return;
    }

    int cols = max(1, int(miniW - 12));
    float scaleY = (miniH * 0.42f);

    stroke(90, 200, 255); strokeWeight(1);

    for (int i = 0; i < cols; i++) {
      float px = left + i;
      float t = (i / (float)(cols - 1)) * A.durationSec;

      float idxF = t / A.wfHopSec;
      int idx0 = floor(idxF);
      int idx1 = min(A.wfMin.length - 1, idx0 + 1);
      float frac = constrain(idxF - idx0, 0, 1);
      float vMin = lerp(A.wfMin[idx0], A.wfMin[idx1], frac);
      float vMax = lerp(A.wfMax[idx0], A.wfMax[idx1], frac);

      line(px, cy - vMax * scaleY, px, cy - vMin * scaleY);
    }

    float ratio = (A.durationSec > 0) ? (playheadSec / A.durationSec) : 0;
    float lineX = left + constrain(ratio, 0, 1) * (right - left);
    stroke(255, 240); strokeWeight(2);
    line(lineX, top, lineX, bottom);
  }

  void drawVinyl() {
    noStroke();
    fill(30);
    rect(diskX - 8, diskY - 8, diskSize + 16, diskSize + 16, 10);

    float cx = diskX + diskSize/2.0, cy = diskY + diskSize/2.0;
    float r  = diskSize/2.0;

    noStroke(); fill(18); circle(cx, cy, diskSize);

    stroke(60); strokeWeight(1); noFill();
    for (int i = 0; i < 18; i++) {
      float rr = map(i, 0, 17, r*0.38, r*0.94);
      stroke(40 + (i%2==0 ? 0 : 8));
      ellipse(cx, cy, rr*2, rr*2);
    }

    float handLen = r * 0.90, handBase = r * 0.15;
    float hx0 = cx + cos(vinylAngle + PI) * handBase;
    float hy0 = cy + sin(vinylAngle + PI) * handBase;
    float hx1 = cx + cos(vinylAngle) * handLen;
    float hy1 = cy + sin(vinylAngle) * handLen;

    stroke(0, 120); strokeWeight(6); line(hx0, hy0, hx1, hy1);
    stroke(255, 200, 90); strokeWeight(3); line(hx0, hy0, hx1, hy1);
    noStroke(); fill(255, 200, 90);
    float tipSize = 10, ang = vinylAngle, tx = hx1, ty = hy1;
    float lx = tx + cos(ang + PI*0.5) * tipSize * 0.5, ly = ty + sin(ang + PI*0.5) * tipSize * 0.5;
    float rx = tx + cos(ang - PI*0.5) * tipSize * 0.5, ry = ty + sin(ang - PI*0.5) * tipSize * 0.5;
    triangle(tx, ty, lx, ly, rx, ry);

    fill(230); noStroke(); circle(cx, cy, 6);

    noStroke(); fill(50, 90, 140); circle(cx, cy, r*0.30*2);

    float effBPM = getEffectiveBPM();
    int beatInBar = getCurrentBeatInBar(analysis, playheadSec, effBPM);

    fill(250); textAlign(CENTER, CENTER);
    textSize(16); text(nf(effBPM, 0, 1) + " BPM", cx, cy - 6);
    textSize(22); text("Beat " + beatInBar, cx, cy + 14);
    textSize(14);
  }

  int getCurrentBeatInBar(TrackAnalysis A, float tSec, float effBPM) {
    if (A != null && A.beats != null && !A.beats.isEmpty()) {
      int idx = A.beatIndexAtTime(tSec);
      if (idx < 0) idx = 0;
      return (idx % 4) + 1;
    } else {
      float period = 60.0 / max(1e-3, effBPM);
      int idx = floor(tSec / period);
      return (idx % 4) + 1;
    }
  }
}
