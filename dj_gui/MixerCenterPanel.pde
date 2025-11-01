// Pannello centrale: Volumi Deck A/B, 4 knob filtro per ciascun deck, Crossfader
// Aggiornato:
// - Tasti cuffie per ogni deck (CUE A / CUE B) indipendenti, con indicatore rosso quando attivi.
// - Knob centrale "Phones" per il volume generale cuffie.
// - Metodi setter/getter pubblici per controllo via MIDI.

class MixerCenterPanel {
  Deck deckA, deckB;

  float x, y, w, h;

  Slider volA, volB;

  Knob[] filtA = new Knob[4];
  Knob[] filtB = new Knob[4];
  String[] filtLabels = {"Low", "Mid", "High", "FX"};

  // Crossfader
  Slider cross;

  // Cuffie
  Button btnCueA = new Button("CUE A");
  Button btnCueB = new Button("CUE B");
  boolean cueAOn = false;
  boolean cueBOn = false;

  Knob phonesKnob = new Knob();   // volume generale cuffie (0..1)

  float meterW = 10;
  float meterGap = 6;

  MixerCenterPanel(Deck a, Deck b) {
    this.deckA = a;
    this.deckB = b;

    volA = new Slider(true, 0.8);
    volA.setLabels("Vol A", "", ""); // Etichette min/max rimosse
    volB = new Slider(true, 0.8);
    volB.setLabels("Vol B", "", ""); // Etichette min/max rimosse

    for (int i = 0; i < 4; i++) {
      filtA[i] = new Knob();  filtA[i].setLabels(filtLabels[i] + " A", "", "");  filtA[i].setValue(0.5);
      filtB[i] = new Knob();  filtB[i].setLabels(filtLabels[i] + " B", "", "");  filtB[i].setValue(0.5);
      if (i < 3) { filtA[i].setAccentColor(color(90, 200, 255)); filtB[i].setAccentColor(color(90, 200, 255)); }
      else       { filtA[i].setAccentColor(color(255, 170, 80));  filtB[i].setAccentColor(color(170, 120, 255)); }
    }

    cross = new Slider(false, 0.5);
    cross.setLabels("Crossfader", "A", "B");

    // Cuffie
    phonesKnob.setLabels("Phones", "", "");
    phonesKnob.setAccentColor(color(255, 100, 100));
    phonesKnob.setValue(0.7); // default
  }

  void updateLayout(float x, float y, float w, float h) {
    this.x = x; this.y = y; this.w = w; this.h = h;

    float pad = 16;
    float headerH = 36;

    float columnGap = 24; // spazio tra colonne knob (A/B)

    float topAreaY = y + headerH + pad;
    float topAreaH = h - headerH - pad*3 - 56; // spazio per crossfader & cuffie
    topAreaH = max(160, topAreaH);

    // Knob piccoli (A/B), con più spazio verticale
    float knobGap = 32;
    float smallKnobD = constrain((topAreaH - knobGap * 3) / 4.5, 20, 32);
    float largeKnobD = smallKnobD * 1.2;
    float knobColW = largeKnobD;

    float faderW = 40;
    float gapFaderToKnob = 12;

    // Larghezza totale gruppo: [A fader|VU|knob] + gap + [B knob|VU|fader]
    float groupAW = faderW + meterGap + meterW + gapFaderToKnob + knobColW;
    float groupBW = knobColW + gapFaderToKnob + meterW + meterGap + faderW;
    float totalMid = groupAW + columnGap + groupBW;

    if (totalMid + pad*2 > w) {
      float scale = (w - pad*2 - columnGap) / (groupAW + groupBW);
      faderW = max(28, faderW * scale);
      groupAW = faderW + meterGap + meterW + gapFaderToKnob + knobColW;
      groupBW = knobColW + gapFaderToKnob + meterW + meterGap + faderW;
      totalMid = groupAW + columnGap + groupBW;
    }

    float startX = x + (w - totalMid) / 2.0;
    float faderH = topAreaH;

    // Gruppo A: Fader | VU | Colonna Knob A
    float currentX = startX;
    volA.setBounds(currentX, topAreaY, faderW, faderH);
    currentX += faderW + meterGap;
    float vuAX = currentX;
    currentX += meterW + gapFaderToKnob;
    float colAX = currentX + knobColW/2.0;
    float kTop = topAreaY;
    filtA[0].setBounds(colAX, kTop + smallKnobD/2.0, smallKnobD);
    filtA[1].setBounds(colAX, kTop + smallKnobD + knobGap + smallKnobD/2.0, smallKnobD);
    filtA[2].setBounds(colAX, kTop + 2*(smallKnobD + knobGap) + smallKnobD/2.0, smallKnobD);
    filtA[3].setBounds(colAX, kTop + 3*(smallKnobD + knobGap) + largeKnobD/2.0, largeKnobD);

    // Gap centrale tra colonne di knob
    currentX += knobColW + columnGap;

    // Gruppo B: Colonna Knob B | VU | Fader
    float colBX = currentX + knobColW/2.0;
    filtB[0].setBounds(colBX, kTop + smallKnobD/2.0, smallKnobD);
    filtB[1].setBounds(colBX, kTop + smallKnobD + knobGap + smallKnobD/2.0, smallKnobD);
    filtB[2].setBounds(colBX, kTop + 2*(smallKnobD + knobGap) + smallKnobD/2.0, smallKnobD);
    filtB[3].setBounds(colBX, kTop + 3*(smallKnobD + knobGap) + largeKnobD/2.0, largeKnobD);
    currentX += knobColW + gapFaderToKnob;
    float vuBX = currentX;
    currentX += meterW + meterGap;
    volB.setBounds(currentX, topAreaY, faderW, faderH);

    // Crossfader
    float crossY = y + h - pad - 30;
    float crossH = 20;
    float crossW = w - pad*2;
    cross.setBounds(x + pad, crossY, crossW, crossH);

    // CUE buttons sopra il crossfader, ai lati
    float cueBtnW = 72, cueBtnH = 22;
    float cueY = crossY - cueBtnH - 8;
    btnCueA.setBounds(x + 10, cueY, cueBtnW, cueBtnH);
    btnCueB.setBounds(x + w - 10 - cueBtnW, cueY, cueBtnW, cueBtnH);

    // Knob "Phones" centrale, sopra i tasti CUE
    float phonesD = 34;
    float phonesY = cueY - phonesD/2f - 6;
    phonesKnob.setBounds(x + w/2f, phonesY, phonesD);
  }

  void draw() {
    // Header
    fill(220); textAlign(CENTER, CENTER); textSize(16);
    text("Center Mixer", x + w/2, y + 18); textSize(14);

    // Fader A + VU
    volA.draw();
    drawVUMeter(volA.x + volA.w + meterGap, volA.y, meterW, volA.h, deckA.getLevelLinear() * volA.getValue());

    // Knob A
    for (int i = 0; i < 4; i++) { filtA[i].draw(); }

    // VU B + Fader B
    float vuBX = volB.x - meterGap - meterW;
    drawVUMeter(vuBX, volB.y, meterW, volB.h, deckB.getLevelLinear() * volB.getValue());
    volB.draw();

    // Knob B
    for (int i = 0; i < 4; i++) { filtB[i].draw(); }

    // Phones knob (centrale)
    phonesKnob.draw();

    // Crossfader
    cross.draw();

    // CUE buttons + LED rosso quando attivi
    drawCueButton(btnCueA, cueAOn);
    drawCueButton(btnCueB, cueBOn);
  }

  void drawCueButton(Button b, boolean on) {
    b.draw(on); // usa lo stato per highlight di base
    if (on) {
      // LED rosso in alto a destra del bottone
      noStroke();
      fill(235, 70, 70);
      float cx = b.x + b.w - 8;
      float cy = b.y + 8;
      circle(cx, cy, 8);
    }
  }

  void drawVUMeter(float vx, float vy, float vw, float vh, float levelLin) {
    noStroke(); fill(26); rect(vx, vy, vw, vh, 3);

    stroke(60); strokeWeight(1);
    for (int i = 0; i <= 10; i++) {
      float yy = vy + vh - (vh * i / 10.0);
      line(vx, yy, vx + vw, yy);
    }

    float L = constrain(levelLin, 0, 1);
    int c;
    if (L < 0.7) c = lerpColor(color(70, 210, 90), color(220, 220, 80), L/0.7);
    else         c = lerpColor(color(220, 220, 80), color(230, 70, 70), (L-0.7)/0.3);

    float barH = vh * L;
    noStroke(); fill(c);
    rect(vx + 1, vy + vh - barH, vw - 2, barH, 2);
  }

  // Getter per il volume cuffie e stati CUE
  float getHeadphonesVolume() { return clamp01(phonesKnob.getValue()); }
  boolean isCueAOn() { return cueAOn; }
  boolean isCueBOn() { return cueBOn; }

  // SETTERS per MIDI
  void setVolumeA(float v) { volA.setValue(clamp01(v)); }
  void setVolumeB(float v) { volB.setValue(clamp01(v)); }
  void setCrossfader(float v) { cross.setValue(clamp01(v)); }
  void setFilterA(int idx, float v) { if (idx>=0 && idx<4) filtA[idx].setValue(clamp01(v)); }
  void setFilterB(int idx, float v) { if (idx>=0 && idx<4) filtB[idx].setValue(clamp01(v)); }
  void setHeadphonesVolume(float v) { phonesKnob.setValue(clamp01(v)); }

  void setCueA(boolean on) { cueAOn = on; }
  void setCueB(boolean on) { cueBOn = on; }
  void toggleCueA() { cueAOn = !cueAOn; }
  void toggleCueB() { cueBOn = !cueBOn; }

  float clamp01(float v) { return constrain(v, 0, 1); }

  // ——— Eventi: inoltro ai controlli ———
  void mousePressed(float mx, float my) {
    if (volA.contains(mx, my)) volA.mousePressed(mx, my);
    if (volB.contains(mx, my)) volB.mousePressed(mx, my);
    if (cross.contains(mx, my)) cross.mousePressed(mx, my);

    for (int i = 0; i < 4; i++) {
      if (filtA[i].contains(mx, my)) filtA[i].mousePressed(mx, my);
      if (filtB[i].contains(mx, my)) filtB[i].mousePressed(mx, my);
    }

    if (phonesKnob.contains(mx, my)) phonesKnob.mousePressed(mx, my);

    if (btnCueA.contains(mx, my)) btnCueA.mousePressed(mx, my);
    if (btnCueB.contains(mx, my)) btnCueB.mousePressed(mx, my);
  }

  void mouseDragged(float mx, float my) {
    if (volA.dragging) volA.mouseDragged(mx, my);
    if (volB.dragging) volB.mouseDragged(mx, my);
    if (cross.dragging) cross.mouseDragged(mx, my);

    for (int i = 0; i < 4; i++) {
      if (filtA[i].dragging) filtA[i].mouseDragged(mx, my);
      if (filtB[i].dragging) filtB[i].mouseDragged(mx, my);
    }

    if (phonesKnob.dragging) phonesKnob.mouseDragged(mx, my);
  }

  void mouseReleased(float mx, float my) {
    volA.mouseReleased(mx, my);
    volB.mouseReleased(mx, my);
    cross.mouseReleased(mx, my);

    for (int i = 0; i < 4; i++) {
      filtA[i].mouseReleased(mx, my);
      filtB[i].mouseReleased(mx, my);
    }

    phonesKnob.mouseReleased(mx, my);

    // Toggle CUE A
    if (btnCueA.pressed && btnCueA.contains(mx, my)) {
      cueAOn = !cueAOn;
    }
    btnCueA.mouseReleased(mx, my);

    // Toggle CUE B
    if (btnCueB.pressed && btnCueB.contains(mx, my)) {
      cueBOn = !cueBOn;
    }
    btnCueB.mouseReleased(mx, my);
  }
}
