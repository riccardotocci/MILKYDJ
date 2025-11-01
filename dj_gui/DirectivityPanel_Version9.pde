// DirectivityPanel: globo di direttività con griglia sferica + colorbar + marker livello
// Correzione:
// - Ellissi sottili riposizionate: 2 tra le ellissi spesse, 2 tra la spessa interna e il centro.
// - Nessun testo/etichetta.
// - Slider invisibile (solo interazione), si vede solo il marker del livello.
// - Griglia e assi con stroke minimizzato.

class DirectivityPanel {
  float x, y, w, h;

  // Area globo
  float gx, gy, gw, gh;

  // Colorbar compatta (senza testi)
  float ctrlPad = 4;
  float barW = 18;
  float barH;
  float barX, barY;

  // Slider invisibile (usato solo per input)
  Slider peakSlider;
  final float DB_MIN = -29.1;
  final float DB_MAX = -6.1;
  float peakDb = -12.0;

  DirectivityPanel() {
    peakSlider = new Slider(true, 0.7);
    peakSlider.setLabels("", "", "");
  }

  void setBounds(float x, float y, float w, float h) {
    this.x = x; this.y = y; this.w = w; this.h = h;

    float sliderW = 12; // stretto, solo hit-area
    float rightCol = ctrlPad + barW + 6 + sliderW + ctrlPad;

    float pad = 6;

    gx = x + pad;
    gy = y + pad;
    gw = max(40, w - rightCol - pad*2);
    gh = max(40, h - pad*2);

    barH = h - pad*2 - 2;
    barX = x + w - rightCol + ctrlPad;
    barY = y + (h - barH)/2f;

    float sliderX = barX + barW + 6;
    float sliderY = barY;
    peakSlider.setBounds(sliderX, sliderY, sliderW, barH);
  }

  void draw() {
    noStroke();
    fill(26);
    rect(x, y, w, h, 8);

    drawGlobe();
    drawColorbar();
    drawLevelMarker(); // solo marker del livello, nessuna scala
  }

  // ——— Globo senza testi ———
  void drawGlobe() {
    float cx = gx + gw/2f;
    float cy = gy + gh/2f;
    float rx = gw/2f;
    float ry = gh/2f * 0.90f;

    // Assi centrali spessi
    stroke(230);
    strokeWeight(1.4);
    line(cx - rx, cy, cx + rx, cy); // equatore
    line(cx, cy - ry, cx, cy + ry); // meridiano 0°

    // Paralleli ±30°, ±60° (sottili)
    stroke(200);
    strokeWeight(0.4);
    float[] lats = {30, 60};
    for (float d : lats) {
      float ryy = ry * cos(radians(d));
      noFill();
      ellipse(cx, cy, rx*2, ryy*2);
    }

    // Meridiani verticali
    float sOuter  = 1.00;
    float sMedian = 0.64;
    int thinGroupCount = 2;

    // 1. Esterno (spesso)
    stroke(245);
    strokeWeight(1.6);
    noFill();
    ellipse(cx, cy, (rx*sOuter)*2, ry*2);

    // 2. Gruppo di ellissi sottili tra esterno e mediano
    stroke(220);
    strokeWeight(0.4);
    for (int i = 1; i <= thinGroupCount; i++) {
      float t = i / (float)(thinGroupCount + 1);
      float s = lerp(sOuter, sMedian, t);
      ellipse(cx, cy, (rx*s)*2, ry*2);
    }

    // 3. Mediano (spesso)
    stroke(245);
    strokeWeight(1.4);
    ellipse(cx, cy, (rx*sMedian)*2, ry*2);

    // 4. Gruppo di ellissi sottili tra mediano e centro
    stroke(220);
    strokeWeight(0.4);
    for (int i = 1; i <= thinGroupCount; i++) {
      float t = i / (float)(thinGroupCount + 1);
      float s = lerp(sMedian, 0, t); // da sMedian a 0 (centro)
      ellipse(cx, cy, (rx*s)*2, ry*2);
    }
  }

  // ——— Colorbar senza testi/scale ———
  void drawColorbar() {
    int[] cols = {
      color(248, 233, 37),
      color(120, 205, 100),
      color(56, 195, 190),
      color(56, 100, 190),
      color(26, 50, 100)
    };
    int steps = int(barH);
    noStroke();
    for (int i = 0; i < steps; i++) {
      float t = i / max(1.0, steps - 1.0);
      int c = gradient(cols, t);
      stroke(c);
      line(barX, barY + (barH - 1 - i), barX + barW, barY + (barH - 1 - i)); // 1px
    }
    noFill(); stroke(50); strokeWeight(0.6);
    rect(barX, barY, barW, barH);
  }

  // ——— Solo marker livello corrente ———
  void drawLevelMarker() {
    float t = peakSlider.getValue(); // 0..1
    float yy = barY + (1.0 - t) * barH;

    stroke(255); strokeWeight(0.8);
    line(barX - 4, yy, barX + barW + 4, yy); // tacca fine
    noStroke();
    fill(255, 230);
    circle(barX + barW + 8, yy, 6);          // pallino a destra
  }

  int gradient(int[] cols, float t) {
    t = constrain(t, 0, 1);
    float seg = 1.0 / (cols.length - 1);
    int idx = floor(t / seg);
    idx = constrain(idx, 0, cols.length - 2);
    float lt = (t - idx*seg) / seg;
    return lerpColor(cols[idx], cols[idx+1], lt);
  }

  // ——— Eventi: slider invisibile ma attivo ———
  void mousePressed(float mx, float my) {
    if (peakSlider.contains(mx, my)) peakSlider.mousePressed(mx, my);
  }

  void mouseDragged(float mx, float my) {
    if (peakSlider.dragging) peakSlider.mouseDragged(mx, my);
  }

  void mouseReleased(float mx, float my) {
    if (peakSlider.dragging || peakSlider.contains(mx, my)) {
      peakSlider.mouseReleased(mx, my);
      float t = peakSlider.getValue();
      peakDb = lerp(DB_MIN, DB_MAX, t);
    }
  }
}
