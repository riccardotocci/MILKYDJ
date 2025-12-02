/**
 * MixerCenterPanel.pde
 *
 * Pannello centrale mixer per MILKY_DJ.
 * 
 * COMPONENTI:
 *  - 2 fader verticali volume (Deck A / Deck B)
 *  - 2 VU meter verticali (live level feedback)
 *  - 8 knob filtri (4 per deck: Low/Mid/High/FX)
 *  - 1 crossfader orizzontale (A ←→ B)
 *  - 2 tasti CUE indipendenti (CUE A / CUE B) con LED rosso quando attivi
 *  - 1 knob centrale "Phones" per volume generale cuffie
 *
 * INVIO OSC:
 *  - Al rilascio del mouse, invia crossfader + volume deck A/B a SuperCollider
 *  - Usa osc.crossfader(float) e osc.deckSetVolume(Deck, float)
 *
 * SETTERS PUBBLICI (per controllo MIDI):
 *  - setVolumeA(float), setVolumeB(float), setCrossfader(float)
 *  - setFilterA(int idx, float), setFilterB(int idx, float)
 *  - setHeadphonesVolume(float)
 *  - setCueA(boolean), setCueB(boolean), toggleCueA(), toggleCueB()
 *
 * NOTE:
 *  - Usa i Deck passati nel costruttore per calcolare i livelli VU (deckA.getLevelLinear(), ecc.)
 *  - Il campo osc deve essere assegnato con setOsc(OscBridge) prima dell'uso.
 *  - La funzione draw() disegna tutto; mousePressed/Dragged/Released gestiscono interazione.
 */

class MixerCenterPanel {
  
  // ====================================
  // RIFERIMENTI ESTERNI
  // ====================================
  Deck deckA;
  Deck deckB;
  OscBridge osc;  // <-- Campo dichiarato qui (inizialmente null)

  // ====================================
  // LAYOUT
  // ====================================
  float x, y, w, h;

  // ====================================
  // CONTROLLI UI
  // ====================================
  // Fader volume verticali (Deck A / B)
  Slider volA;
  Slider volB;

  // Knob filtri (4 per deck)
  Knob[] filtA = new Knob[4];
  Knob[] filtB = new Knob[4];
  String[] filtLabels = {"Low", "Mid", "High", "FX"};

  // Crossfader orizzontale
  Slider cross;

  // Tasti CUE (indipendenti)
  Button btnCueA;
  Button btnCueB;
  boolean cueAOn = false;
  boolean cueBOn = false;

  // Knob volume cuffie (centrale)
  Knob phonesKnob;

  // ====================================
  // PARAMETRI GRAFICI
  // ====================================
  float meterW = 10;         // larghezza VU meter
  float meterGap = 6;        // gap tra fader e VU

  // ====================================
  // COSTRUTTORE
  // ====================================
  MixerCenterPanel(Deck a, Deck b) {
    // Inizializza riferimenti
    this.deckA = a;
    this.deckB = b;
    this.osc = null;  // verrà assegnato dopo con setOsc()

    // Fader volume (verticali)
    volA = new Slider(true, 0.8);
    volA.setLabels("Vol A", "", "");

    volB = new Slider(true, 0.8);
    volB.setLabels("Vol B", "", "");

    // Knob filtri (4 per deck)
    for (int i = 0; i < 4; i++) {
      filtA[i] = new Knob();
      filtA[i].setLabels(filtLabels[i] + " A", "", "");
      filtA[i].setValue(0.5);

      filtB[i] = new Knob();
      filtB[i].setLabels(filtLabels[i] + " B", "", "");
      filtB[i].setValue(0.5);

      // Colori accent (Low/Mid/High blu, FX arancio/viola)
      if (i < 3) {
        filtA[i].setAccentColor(color(90, 200, 255));
        filtB[i].setAccentColor(color(90, 200, 255));
      } else {
        filtA[i].setAccentColor(color(255, 170, 80));
        filtB[i].setAccentColor(color(170, 120, 255));
      }
    }

    // Crossfader (orizzontale)
    cross = new Slider(false, 0.5);
    cross.setLabels("Crossfader", "A", "B");

    // Tasti CUE
    btnCueA = new Button("CUE A");
    btnCueB = new Button("CUE B");

    // Knob cuffie centrale
    phonesKnob = new Knob();
    phonesKnob.setLabels("Phones", "", "");
    phonesKnob.setAccentColor(color(255, 100, 100));
    phonesKnob.setValue(0.7); // default 70%
  }

  // ====================================
  // SETTER OSC (chiamato da Main dopo la creazione)
  // ====================================
  void setOsc(OscBridge o) {
    this.osc = o;
  }

  // ====================================
  // UPDATE LAYOUT
  // ====================================
  void updateLayout(float x, float y, float w, float h) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;

    float pad = 16;
    float headerH = 36;

    // Area disponibile per i controlli (sotto header)
    float topAreaY = y + headerH + pad;
    float topAreaH = h - headerH - pad * 3 - 56; // spazio per crossfader + cuffie
    topAreaH = max(160, topAreaH);

    // Gap tra colonne di knob (A/B)
    float columnGap = 24;

    // Dimensioni knob (piccoli e grandi)
    float knobGap = 32;
    float smallKnobD = constrain((topAreaH - knobGap * 3) / 4.5, 20, 32);
    float largeKnobD = smallKnobD * 1.2;
    float knobColW = largeKnobD;

    // Dimensioni fader
    float faderW = 40;
    float gapFaderToKnob = 12;

    // Calcolo larghezza totale gruppo A + gruppo B
    float groupAW = faderW + meterGap + meterW + gapFaderToKnob + knobColW;
    float groupBW = knobColW + gapFaderToKnob + meterW + meterGap + faderW;
    float totalMid = groupAW + columnGap + groupBW;

    // Scala se troppo largo
    if (totalMid + pad * 2 > w) {
      float scale = (w - pad * 2 - columnGap) / (groupAW + groupBW);
      faderW = max(28, faderW * scale);
      groupAW = faderW + meterGap + meterW + gapFaderToKnob + knobColW;
      groupBW = knobColW + gapFaderToKnob + meterW + meterGap + faderW;
      totalMid = groupAW + columnGap + groupBW;
    }

    // Punto di partenza centrato
    float startX = x + (w - totalMid) / 2.0;
    float faderH = topAreaH;

    // === GRUPPO A (sinistra): Fader | VU | Colonna Knob ===
    float currentX = startX;

    // Fader A
    volA.setBounds(currentX, topAreaY, faderW, faderH);
    currentX += faderW + meterGap;

    // VU A (solo posizione, disegno in draw())
    float vuAX = currentX;
    currentX += meterW + gapFaderToKnob;

    // Colonna knob A (centrata verticalmente)
    float colAX = currentX + knobColW / 2.0;
    float kTop = topAreaY;

    filtA[0].setBounds(colAX, kTop + smallKnobD / 2.0, smallKnobD);
    filtA[1].setBounds(colAX, kTop + smallKnobD + knobGap + smallKnobD / 2.0, smallKnobD);
    filtA[2].setBounds(colAX, kTop + 2 * (smallKnobD + knobGap) + smallKnobD / 2.0, smallKnobD);
    filtA[3].setBounds(colAX, kTop + 3 * (smallKnobD + knobGap) + largeKnobD / 2.0, largeKnobD);

    // Gap centrale tra colonne di knob
    currentX += knobColW + columnGap;

    // === GRUPPO B (destra): Colonna Knob | VU | Fader ===
    float colBX = currentX + knobColW / 2.0;

    filtB[0].setBounds(colBX, kTop + smallKnobD / 2.0, smallKnobD);
    filtB[1].setBounds(colBX, kTop + smallKnobD + knobGap + smallKnobD / 2.0, smallKnobD);
    filtB[2].setBounds(colBX, kTop + 2 * (smallKnobD + knobGap) + smallKnobD / 2.0, smallKnobD);
    filtB[3].setBounds(colBX, kTop + 3 * (smallKnobD + knobGap) + largeKnobD / 2.0, largeKnobD);

    currentX += knobColW + gapFaderToKnob;

    // VU B
    float vuBX = currentX;
    currentX += meterW + meterGap;

    // Fader B
    volB.setBounds(currentX, topAreaY, faderW, faderH);

    // === CROSSFADER (fondo) ===
    float crossY = y + h - pad - 30;
    float crossH = 20;
    float crossW = w - pad * 2;
    cross.setBounds(x + pad, crossY, crossW, crossH);

    // === TASTI CUE (sopra crossfader, ai lati) ===
    float cueBtnW = 72;
    float cueBtnH = 22;
    float cueY = crossY - cueBtnH - 8;

    btnCueA.setBounds(x + 10, cueY, cueBtnW, cueBtnH);
    btnCueB.setBounds(x + w - 10 - cueBtnW, cueY, cueBtnW, cueBtnH);

    // === KNOB PHONES (centrale, sopra tasti CUE) ===
    float phonesD = 34;
    float phonesY = cueY - phonesD / 2.0 - 6;
    phonesKnob.setBounds(x + w / 2.0, phonesY, phonesD);
  }

  // ====================================
  // DRAW
  // ====================================
  void draw() {
    // Header
    fill(220);
    textAlign(CENTER, CENTER);
    textSize(16);
    text("Center Mixer", x + w / 2, y + 18);
    textSize(14);

    // Fader A + VU A
    volA.draw();
    float vuAX = volA.x + volA.w + meterGap;
    drawVUMeter(vuAX, volA.y, meterW, volA.h, deckA.getLevelLinear() * volA.getValue());

    // Knob A (4)
    for (int i = 0; i < 4; i++) {
      filtA[i].draw();
    }

    // VU B + Fader B
    float vuBX = volB.x - meterGap - meterW;
    drawVUMeter(vuBX, volB.y, meterW, volB.h, deckB.getLevelLinear() * volB.getValue());
    volB.draw();

    // Knob B (4)
    for (int i = 0; i < 4; i++) {
      filtB[i].draw();
    }

    // Knob Phones (centrale)
    phonesKnob.draw();

    // Crossfader
    cross.draw();

    // Tasti CUE + LED rosso quando attivi
    drawCueButton(btnCueA, cueAOn);
    drawCueButton(btnCueB, cueBOn);
  }

  // ====================================
  // DRAW CUE BUTTON (con LED rosso se on)
  // ====================================
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

  // ====================================
  // DRAW VU METER (verticale, 10 tacche)
  // ====================================
  void drawVUMeter(float vx, float vy, float vw, float vh, float levelLin) {
    // Background
    noStroke();
    fill(26);
    rect(vx, vy, vw, vh, 3);

    // Tacche orizzontali
    stroke(60);
    strokeWeight(1);
    for (int i = 0; i <= 10; i++) {
      float yy = vy + vh - (vh * i / 10.0);
      line(vx, yy, vx + vw, yy);
    }

    // Barra livello (colore dinamico verde→giallo→rosso)
    float L = constrain(levelLin, 0, 1);
    int c;
    if (L < 0.7) {
      c = lerpColor(color(70, 210, 90), color(220, 220, 80), L / 0.7);
    } else {
      c = lerpColor(color(220, 220, 80), color(230, 70, 70), (L - 0.7) / 0.3);
    }

    float barH = vh * L;
    noStroke();
    fill(c);
    rect(vx + 1, vy + vh - barH, vw - 2, barH, 2);
  }

  // ====================================
  // GETTER (per MIDI o feedback esterno)
  // ====================================
  float getHeadphonesVolume() {
    return clamp01(phonesKnob.getValue());
  }

  boolean isCueAOn() {
    return cueAOn;
  }

  boolean isCueBOn() {
    return cueBOn;
  }

  // ====================================
  // SETTERS PUBBLICI (per MIDI)
  // ====================================
  void setVolumeA(float v) {
    volA.setValue(clamp01(v));
  }

  void setVolumeB(float v) {
    volB.setValue(clamp01(v));
  }

  void setCrossfader(float v) {
    cross.setValue(clamp01(v));
  }

  void setFilterA(int idx, float v) {
    if (idx >= 0 && idx < 4) filtA[idx].setValue(clamp01(v));
  }

  void setFilterB(int idx, float v) {
    if (idx >= 0 && idx < 4) filtB[idx].setValue(clamp01(v));
  }

  void setHeadphonesVolume(float v) {
    phonesKnob.setValue(clamp01(v));
  }

  void setCueA(boolean on) {
    cueAOn = on;
  }

  void setCueB(boolean on) {
    cueBOn = on;
  }

  void toggleCueA() {
    cueAOn = !cueAOn;
  }

  void toggleCueB() {
    cueBOn = !cueBOn;
  }

  // ====================================
  // UTILITY CLAMP
  // ====================================
  float clamp01(float v) {
    return constrain(v, 0, 1);
  }

  // ====================================
  // EVENTI MOUSE: PRESSED
  // ====================================
  void mousePressed(float mx, float my) {
    // Fader volume
    if (volA.contains(mx, my)) volA.mousePressed(mx, my);
    if (volB.contains(mx, my)) volB.mousePressed(mx, my);

    // Crossfader
    if (cross.contains(mx, my)) cross.mousePressed(mx, my);

    // Knob filtri (4+4)
    for (int i = 0; i < 4; i++) {
      if (filtA[i].contains(mx, my)) filtA[i].mousePressed(mx, my);
      if (filtB[i].contains(mx, my)) filtB[i].mousePressed(mx, my);
    }

    // Knob phones
    if (phonesKnob.contains(mx, my)) phonesKnob.mousePressed(mx, my);

    // Tasti CUE
    if (btnCueA.contains(mx, my)) btnCueA.mousePressed(mx, my);
    if (btnCueB.contains(mx, my)) btnCueB.mousePressed(mx, my);
  }

  // ====================================
  // EVENTI MOUSE: DRAGGED
  // ====================================
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

  // ====================================
  // EVENTI MOUSE: RELEASED
  // ====================================
  void mouseReleased(float mx, float my) {
    // Rilascia tutti i controlli
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
      // Invia comando a SuperCollider
      if (osc != null) osc.deckSetCueMonitor(deckA, cueAOn);
    }
    btnCueA.mouseReleased(mx, my);

    // Toggle CUE B
    if (btnCueB.pressed && btnCueB.contains(mx, my)) {
      cueBOn = !cueBOn;
      // Invia comando a SuperCollider
      if (osc != null) osc.deckSetCueMonitor(deckB, cueBOn);
    }
    btnCueB.mouseReleased(mx, my);

    // ====================================
    // INVIO OSC AL RILASCIO (se osc != null)
    // ====================================
    if (osc != null) {
      osc.crossfader(cross.getValue());
      osc.deckSetVolume(deckA, volA.getValue());
      osc.deckSetVolume(deckB, volB.getValue());
    }
  }
}
