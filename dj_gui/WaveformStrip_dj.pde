// WaveformStrip_dj.pde
// Strip della waveform principale con:
// - Playhead centrato (la waveform scorre sotto il cursore centrale)
// - Beat markers + downbeat evidenziato
// - Overlay del loop (IN/OUT)
// - Badge BPM e stato PLAY/STOP
// - Scrubbing con mouse (click + drag) che invia /dj3d/deck/seek via OscBridge
// - Direzione di controllo invertibile (drag a destra va indietro o avanti a scelta)
// - Throttle dell’invio OSC per evitare flooding
//
// Usa deck.analysis (TrackAnalysis) e campi del Deck:
//   deck.playheadSec, deck.loopInSec, deck.loopOutSec, deck.loopEnabled,
//   deck.getEffectiveBPM(), deck.playBtn.getPlaying(), deck.isAnalyzing
//
// Per attivare l’OSC: chiama setOsc(oscBridge) dopo aver istanziato la classe.
// Per invertire la direzione: setInvertControl(true).
//
// NOTE:
// - pixelsPerBeat determina lo zoom orizzontale dinamico (viene aggiornato dall’esterno).
// - Il metodo update(dt) è lasciato vuoto per eventuali future animazioni locali.
// - La logica di mapping pixel→tempo usa il playhead di partenza al momento del mousePressed,
//   così il drag è relativo (tipo “trascino la waveform sotto il playhead”).
//
// Dipendenze: la classe Deck e OscBridge devono essere già definiti.

class WaveformStrip {
  // ------------------------------
  // Riferimenti
  // ------------------------------
  String label;
  Deck deck;
  OscBridge osc;     // assegnato con setOsc()

  // ------------------------------
  // Layout / stato grafico
  // ------------------------------
  float x, y, w, h;
  float amp = 1.0;           // scaling verticale (peak envelope)
  float pixelsPerBeat = 140; // zoom orizzontale

  // ------------------------------
  // Interazione mouse
  // ------------------------------
  boolean draggingWave = false;
  float dragWaveStartPlayhead = 0.0;
  float lastSentSeekSec = -999f;
  boolean invertControl = true;   // true = drag a destra -> tempo indietro (wave “scorre sotto”)
  float seekThrottleDelta = 0.05f; // invia /seek solo se variazione > 50ms

  // ------------------------------
  // Costruttore
  // ------------------------------
  WaveformStrip(String label, Deck deck) {
    this.label = label;
    this.deck  = deck;
  }

  // ------------------------------
  // Setters esterni
  // ------------------------------
  void setOsc(OscBridge o) { this.osc = o; }
  void setBounds(float x, float y, float w, float h) { this.x = x; this.y = y; this.w = w; this.h = h; }
  void setPixelsPerBeat(float ppb) { pixelsPerBeat = max(10, ppb); }
  void setInvertControl(boolean inv) { invertControl = inv; }

  // ------------------------------
  // Update (placeholder)
  // ------------------------------
  void update(float dt) {
    // Nessuna animazione interna per ora.
  }

  // ------------------------------
  // Draw entry point
  // ------------------------------
  void draw() {
    noStroke();
    fill(24);
    rect(x, y, w, h, 8);

    // Titolo
    fill(180);
    textAlign(LEFT, TOP);
    text(label, x + 10, y + 8);

    // Linea centrale (baseline)
    stroke(44);
    strokeWeight(1);
    float cy = y + h/2f;
    line(x + 8, cy, x + w - 8, cy);

    // Se analisi non pronta mostra placeholder
    if (deck == null || deck.analysis == null || deck.isAnalyzing) {
      fill(120);
      textAlign(CENTER, CENTER);
      textSize(14);
      text(deck != null && deck.isAnalyzing ? "Analyzing..." : "Load a track", x + w/2f, y + h/2f);
    } else {
      drawWave();
      drawLoopOverlay();
      drawBeatMarkers();
    }

    drawStatusBadges();
  }

  // ------------------------------
  // Disegno waveform (playhead centrato)
  // ------------------------------
  void drawWave() {
    TrackAnalysis A = deck.analysis;
    float cy = y + h/2f;

    if (A == null || A.wfMin == null || A.wfMax == null) {
      stroke(90, 200, 255, 120);
      line(x + 6, cy, x + w - 6, cy);
      return;
    }

    float effBPM   = max(1e-4, deck.getEffectiveBPM());
    float pxPerSec = pixelsPerBeat * (effBPM / 60.0); // beat → second conversion
    float left     = x + 6;
    float right    = x + w - 6;
    float centerX  = x + w/2f;
    float scaleY   = (h * 0.46f) * amp;

    int cols = max(1, int(w - 12));
    float tNow = deck.playheadSec;

    stroke(90, 200, 255);
    strokeWeight(1);

    for (int i = 0; i < cols; i++) {
      float px = left + i;
      float dt = (px - centerX) / pxPerSec;
      float t  = tNow + dt;
      if (t < 0 || t >= A.durationSec) continue;

      float idxF = t / A.wfHopSec;
      int idx0   = floor(idxF);
      int idx1   = min(A.wfMin.length - 1, idx0 + 1);
      float frac = constrain(idxF - idx0, 0, 1);

      float vMin = lerp(A.wfMin[idx0], A.wfMin[idx1], frac);
      float vMax = lerp(A.wfMax[idx0], A.wfMax[idx1], frac);

      float yTop = cy - vMax * scaleY;
      float yBot = cy - vMin * scaleY;
      line(px, yTop, px, yBot);
    }

    // Playhead centrale
    stroke(255, 240);
    strokeWeight(2);
    line(centerX, y + 6, centerX, y + h - 6);
  }

  // ------------------------------
  // Loop overlay
  // ------------------------------
  void drawLoopOverlay() {
    Deck d = deck;
    float inSec  = d.loopInSec;
    float outSec = d.loopOutSec;
    if (!d.loopEnabled || inSec < 0 || outSec <= inSec) return;
    TrackAnalysis A = d.analysis;
    if (A == null) return;

    float effBPM   = max(1e-4, d.getEffectiveBPM());
    float pxPerSec = pixelsPerBeat * (effBPM / 60.0);
    float centerX  = x + w/2f;
    float viewL = x + 6;
    float viewR = x + w - 6;

    int edgeCol = color(255, 200, 90, 220);
    int fillCol = color(120, 200, 140, 60);

    float xIn  = centerX + (inSec  - d.playheadSec) * pxPerSec;
    float xOut = centerX + (outSec - d.playheadSec) * pxPerSec;

    float xa = max(viewL, min(xIn, xOut));
    float xb = min(viewR, max(xIn, xOut));
    if (xa > xb) return;

    noStroke(); fill(fillCol);
    rect(xa, y + 6, xb - xa, h - 12);

    stroke(0, 120);
    strokeWeight(3);
    line(xa, y + 6, xa, y + h - 6);
    line(xb, y + 6, xb, y + h - 6);

    stroke(edgeCol);
    strokeWeight(2);
    line(xa, y + 6, xa, y + h - 6);
    line(xb, y + 6, xb, y + h - 6);
  }

  // ------------------------------
  // Beat markers (usa grid analizzata se presente)
  // ------------------------------
  void drawBeatMarkers() {
    TrackAnalysis A = deck.analysis;
    float effBPM   = max(1e-4, deck.getEffectiveBPM());
    float pxPerSec = pixelsPerBeat * (effBPM / 60.0);
    float centerX  = x + w/2f;

    float secondsSpan = (w - 12) / pxPerSec;
    float tNow   = deck.playheadSec;
    float tLeft  = tNow - secondsSpan / 2f;
    float tRight = tNow + secondsSpan / 2f;

    boolean drewAny = false;

    if (A != null && A.beats != null && !A.beats.isEmpty() && !deck.isAnalyzing) {
      IntRange range = A.beatIndexRangeBetween(tLeft, tRight);
      if (range != null) {
        for (int i = range.i0; i <= range.i1; i++) {
          float bt = A.beats.get(i);
          float lineX = centerX + (bt - tNow) * pxPerSec;
          if (lineX < x + 6 || lineX > x + w - 6) continue;
          boolean downbeat = (i % 4 == 0);

          stroke(0, 120);
          strokeWeight(downbeat ? 3.2 : 2.2);
          line(lineX, y + 6, lineX, y + h - 6);

          stroke(downbeat ? color(255, 170, 80, 210) : color(140, 180, 210, 190));
          strokeWeight(downbeat ? 2.0 : 1.2);
            line(lineX, y + 6, lineX, y + h - 6);

          String labelTxt = str((i % 4) + 1);
          float tw = textWidth(labelTxt) + 6;
          float th = 14;
          noStroke();
          fill(20, 200);
          rect(lineX - tw/2f, y + 6, tw, th, 3);
          fill(240);
          textAlign(CENTER, CENTER);
          textSize(12);
          text(labelTxt, lineX, y + 6 + th/2f);
          textSize(14);

          drewAny = true;
        }
      }
    }

    // Fallback: segna battute basiche se non c’è analisi
    if (!drewAny) {
      float period = 60.0 / effBPM;
      float base = floor(tLeft / period) * period;
      for (int k = 0; ; k++) {
        float bt = base + k * period;
        if (bt > tRight) break;
        float lineX = centerX + (bt - tNow) * pxPerSec;
        if (lineX < x + 6 || lineX > x + w - 6) continue;
        boolean downbeat = (k % 4 == 0);

        stroke(downbeat ? color(255, 170, 80, 200) : color(140, 180, 210, 170));
        strokeWeight(downbeat ? 2.0 : 1.0);
        line(lineX, y + 6, lineX, y + h - 6);

        if (downbeat) {
          String txt = "1";
          float tw = textWidth(txt) + 6;
          float th = 14;
          noStroke();
          fill(20, 200);
          rect(lineX - tw/2f, y + 6, tw, th, 3);
          fill(240);
          textAlign(CENTER, CENTER);
          textSize(12);
          text(txt, lineX, y + 6 + th/2f);
          textSize(14);
        }
      }
    }
  }

  // ------------------------------
  // Badge BPM + stato PLAY/STOP
  // ------------------------------
  void drawStatusBadges() {
    boolean playing = deck.playBtn.getPlaying();
    float effBPM    = deck.getEffectiveBPM();
    String status   = playing ? "PLAY" : "STOP";
    String bpmStr   = nf(effBPM, 0, 1) + " BPM";

    float bx = x + w - 10;
    float by = y + 10;
    float th = 22;

    // BPM
    String tText = bpmStr;
    float tw = textWidth(tText) + 14;
    noStroke();
    fill(40, 40, 40, 210);
    rect(bx - tw, by, tw, th, 6);
    fill(220);
    textAlign(RIGHT, CENTER);
    text(tText, bx - 7, by + th/2f);

    // Stato
    String sText = status;
    float sw = textWidth(sText) + 14;
    float sy = by + th + 6;
    fill(playing ? color(80, 160, 110, 220) : color(90, 90, 90, 220));
    rect(bx - sw, sy, sw, th, 6);
    fill(240);
    textAlign(RIGHT, CENTER);
    text(sText, bx - 7, sy + th/2f);
  }

  // ------------------------------
  // Interazione mouse
  // ------------------------------
  boolean contains(float mx, float my) {
    return mx >= x && mx <= x + w && my >= y && my <= y + h;
  }

  void mousePressed(float mx, float my) {
    if (!contains(mx, my)) return;
    if (deck == null || deck.analysis == null || deck.isAnalyzing) return;

    draggingWave = true;
    dragWaveStartPlayhead = deck.playheadSec;
    updatePlayheadFromMouse(mx);
    sendSeekImmediate(); // primo seek immediato
  }

  void mouseDragged(float mx, float my) {
    if (!draggingWave) return;
    updatePlayheadFromMouse(mx);
    if (osc != null && abs(deck.playheadSec - lastSentSeekSec) > seekThrottleDelta) {
      osc.deckSeek(deck, deck.playheadSec);
      lastSentSeekSec = deck.playheadSec;
    }
  }

  void mouseReleased(float mx, float my) {
    if (draggingWave) {
      sendSeekImmediate(); // seek finale preciso
    }
    draggingWave = false;
  }

  // ------------------------------
  // Mapping pixel -> tempo (relativo al punto iniziale)
  // ------------------------------
  void updatePlayheadFromMouse(float mx) {
    TrackAnalysis A = deck.analysis;
    if (A == null) return;

    float effBPM   = max(1e-4, deck.getEffectiveBPM());
    float pxPerSec = pixelsPerBeat * (effBPM / 60.0);
    float centerX  = x + w/2f;

    // delta tempo relativo
    float dtRaw = (mx - centerX) / pxPerSec;
    float dt    = invertControl ? -dtRaw : dtRaw;

    float t = dragWaveStartPlayhead + dt;
    t = constrain(t, 0, A.durationSec);
    deck.seekToSeconds(t);
  }

  // ------------------------------
  // Invio seek immediato (senza throttle)
  // ------------------------------
  void sendSeekImmediate() {
    if (osc != null) {
      osc.deckSeek(deck, deck.playheadSec);
      lastSentSeekSec = deck.playheadSec;
    }
  }
}
