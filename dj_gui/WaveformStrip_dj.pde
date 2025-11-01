// WaveformStrip: Corretto per essere compatibile con la classe Deck_dj.pde
// - Usa deck.analysis per verificare se il brano è caricato e per ottenere i dati della forma d'onda.
// - Mantiene la visualizzazione con playhead centrato e beat markers.

class WaveformStrip {
  String label;
  Deck deck;

  float x, y, w, h;
  float amp = 1.0;
  float pixelsPerBeat = 140;

  WaveformStrip(String label, Deck deck) {
    this.label = label;
    this.deck = deck;
  }

  void setBounds(float x, float y, float w, float h) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }

  void setPixelsPerBeat(float ppb) {
    pixelsPerBeat = max(10, ppb);
  }

  void update(float dt) {}

  void draw() {
    noStroke();
    fill(24);
    rect(x, y, w, h, 8);

    fill(180);
    textAlign(LEFT, TOP);
    text(label, x + 10, y + 8);

    stroke(44);
    strokeWeight(1);
    float cy = y + h/2;
    line(x + 8, cy, x + w - 8, cy);

    // Controlla se l'analisi è completa prima di disegnare
    if (deck == null || deck.analysis == null || deck.isAnalyzing) {
      fill(120);
      textAlign(CENTER, CENTER);
      textSize(14);
      text(deck.isAnalyzing ? "Analyzing..." : "Load a track", x + w / 2, y + h / 2);
    } else {
      drawWave();
      drawLoopOverlay();
      drawBeatMarkers();
    }
    
    // I badge di stato vengono disegnati sempre
    drawStatusBadges();
  }

  void drawWave() {
    TrackAnalysis A = deck.analysis;
    float cy = y + h/2;
    // Questo controllo è ridondante se già fatto in draw(), ma è una sicurezza
    if (A == null || A.wfMin == null || A.wfMax == null) {
      stroke(90, 200, 255, 120);
      line(x + 6, cy, x + w - 6, cy);
      return;
    }

    float effBPM = max(1e-4, deck.getEffectiveBPM());
    float pxPerSec = pixelsPerBeat * (effBPM / 60.0);

    float left = x + 6;
    float right = x + w - 6;
    float centerX = x + w/2.0;

    float scaleY = (h * 0.46f) * amp;

    int cols = max(1, int(w - 12));
    float tNow = deck.playheadSec;

    stroke(90, 200, 255);
    strokeWeight(1);

    for (int i = 0; i < cols; i++) {
      float px = left + i;

      float dt = (px - centerX) / pxPerSec;
      float t = tNow + dt;
      if (t < 0 || t >= A.durationSec) continue;

      float idxF = t / A.wfHopSec;
      int idx0 = floor(idxF);
      int idx1 = min(A.wfMin.length - 1, idx0 + 1);
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

  void drawLoopOverlay() {
    Deck d = deck;
    float inSec = d.loopInSec;
    float outSec = d.loopOutSec;
    if (inSec < 0 && outSec < 0) return;
    TrackAnalysis A = d.analysis;
    if (A == null) return;

    float effBPM = max(1e-4, d.getEffectiveBPM());
    float pxPerSec = pixelsPerBeat * (effBPM / 60.0);
    float centerX = x + w/2.0;

    float viewL = x + 6;
    float viewR = x + w - 6;

    int edgeCol = color(255, 200, 90, 220);
    int fillCol = color(120, 200, 140, 60);

    float xIn = centerX + (inSec - d.playheadSec) * pxPerSec;
    float xOut = centerX + (outSec - d.playheadSec) * pxPerSec;

    if (inSec >= 0 && (outSec < 0 || outSec <= inSec)) {
      if (xIn >= viewL && xIn <= viewR) {
        stroke(0, 120); strokeWeight(3);
        line(xIn, y + 6, xIn, y + h - 6);
        stroke(edgeCol); strokeWeight(2);
        line(xIn, y + 6, xIn, y + h - 6);
      }
      return;
    }

    if (inSec >= 0 && outSec > inSec) {
      float xa = max(viewL, min(xIn, xOut));
      float xb = min(viewR, max(xIn, xOut));
      if (xa <= xb) {
        noStroke(); fill(fillCol);
        rect(xa, y + 6, xb - xa, h - 12);

        stroke(0, 120); strokeWeight(3);
        line(xa, y + 6, xa, y + h - 6);
        line(xb, y + 6, xb, y + h - 6);
        stroke(edgeCol); strokeWeight(2);
        line(xa, y + 6, xa, y + h - 6);
        line(xb, y + 6, xb, y + h - 6);
      }
    }
  }

  void drawBeatMarkers() {
    float effBPM = max(1e-4, deck.getEffectiveBPM());
    float pxPerSec = pixelsPerBeat * (effBPM / 60.0);

    float centerX = x + w/2.0;
    float secondsSpan = (w - 12) / pxPerSec;
    float tNow = deck.playheadSec;
    float tLeft = tNow - secondsSpan/2.0;
    float tRight = tNow + secondsSpan/2.0;

    TrackAnalysis A = deck.analysis;

    boolean drewAny = false;

    if (A != null && A.beats != null && !A.beats.isEmpty() && !deck.isAnalyzing) {
      IntRange range = A.beatIndexRangeBetween(tLeft, tRight);
      if (range != null) {
        for (int i = range.i0; i <= range.i1; i++) {
          float bt = A.beats.get(i);
          float lineX = centerX + (bt - tNow) * pxPerSec;
          if (lineX < x + 6 || lineX > x + w - 6) continue;

          boolean downbeat = (i % 4 == 0);
          stroke(0, 120); strokeWeight(downbeat ? 3.2 : 2.2);
          line(lineX, y + 6, lineX, y + h - 6);
          stroke(downbeat ? color(255, 170, 80, 210) : color(140, 180, 210, 190));
          strokeWeight(downbeat ? 2.0 : 1.2);
          line(lineX, y + 6, lineX, y + h - 6);

          String labelTxt = str((i % 4) + 1);
          float tw = textWidth(labelTxt) + 6, th = 14;
          noStroke(); fill(20, 200);
          rect(lineX - tw/2, y + 6, tw, th, 3);
          fill(240); textAlign(CENTER, CENTER); textSize(12);
          text(labelTxt, lineX, y + 6 + th/2); textSize(14);
          drewAny = true;
        }
      }
    }

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
          float tw = textWidth(txt) + 6, th = 14;
          noStroke(); fill(20, 200);
          rect(lineX - tw/2, y + 6, tw, th, 3);
          fill(240); textAlign(CENTER, CENTER); textSize(12);
          text(txt, lineX, y + 6 + th/2); textSize(14);
        }
      }
    }
  }

  void drawStatusBadges() {
    boolean playing = deck.playBtn.getPlaying(); // Usa il riferimento corretto
    float effBPM = deck.getEffectiveBPM();
    String status = playing ? "PLAY" : "STOP";
    String bpmStr = nf(effBPM, 0, 1) + " BPM";

    float bx = x + w - 10;
    float by = y + 10;
    float th = 22;

    String tText = bpmStr;
    float tw = textWidth(tText) + 14;
    noStroke();
    fill(40, 40, 40, 210);
    rect(bx - tw, by, tw, th, 6);
    fill(220);
    textAlign(RIGHT, CENTER);
    text(tText, bx - 7, by + th/2);

    String sText = status;
    float sw = textWidth(sText) + 14;
    float sy = by + th + 6;
    fill(playing ? color(80, 160, 110, 220) : color(90, 90, 90, 220));
    rect(bx - sw, sy, sw, th, 6);
    fill(240);
    textAlign(RIGHT, CENTER);
    text(sText, bx - 7, sy + th/2);
  }
}
