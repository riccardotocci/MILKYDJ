// Schermata Settings: selezione decoder + due editor (uno per Binaural, uno per Simple)

class SettingsScreen {
  OscBridge osc;

  // Radio decoder
  Button btnBinaural = new Button("Binaural");
  Button btnSimple   = new Button("Simple");

  // Editor toggle per ciascun decoder
  ToggleButton btnEditBinaural = new ToggleButton("Editor Binaural", false);
  ToggleButton btnEditSimple   = new ToggleButton("Editor Simple", false);
  

  String activeDecoder = "binaural";   // stato attivo
  boolean editorOpen = false;          // editor del decoder corrente aperto?
  String pendingEditorAfterSwitch = null;

  float x,y,w,h;

  SettingsScreen(OscBridge osc) { this.osc = osc; }

// Sostituisci l'intera funzione setActiveDecoder con questa:

  void setActiveDecoder(String t) {
    if (t == null) return;
    t = t.toLowerCase();
    
    // --- CORREZIONE QUI ---
    // SuperCollider risponde con "simpledecoder" o "binauraldecoder".
    // Dobbiamo mapparli correttamente alle stringhe brevi "simple" e "binaural" usate dalla GUI.
    if (t.contains("simple")) {
      activeDecoder = "simple";
    } else if (t.contains("binaural")) {
      activeDecoder = "binaural";
    } else {
      // Fallback
      activeDecoder = "binaural";
    }

    // Logica per l'apertura automatica dell'editor dopo lo switch
    if (pendingEditorAfterSwitch != null && pendingEditorAfterSwitch.equals(activeDecoder)) {
      if (osc != null) osc.decoderEditor(true);
      editorOpen = true;
      if (activeDecoder.equals("binaural")) {
        btnEditBinaural.state = true;
        btnEditSimple.state = false;
      } else {
        btnEditSimple.state = true;
        btnEditBinaural.state = false;
      }
      pendingEditorAfterSwitch = null;
    } else {
      // Se si è cambiato decoder e un editor era aperto, chiudilo
      if (editorOpen) {
        if (osc != null) osc.decoderEditor(false);
        editorOpen = false;
        btnEditBinaural.state = false;
        btnEditSimple.state = false;
      }
    }
  }

  void updateLayout(float x,float y,float w,float h) {
    this.x=x; this.y=y; this.w=w; this.h=h;
    float headerH = 60;
    float btnW = 150;
    float btnH = 48;
    float gap = 18;

    float rowY = y + headerH + 18;
    float totalW = btnW*2 + gap;
    float startX = x + (w - totalW)/2f;
    btnBinaural.setBounds(startX, rowY, btnW, btnH);
    btnSimple.setBounds(startX + btnW + gap, rowY, btnW, btnH);

    float editY = rowY + btnH + 50;
    btnEditBinaural.setBounds(startX, editY, btnW, btnH);
    btnEditSimple.setBounds(startX + btnW + gap, editY, btnW, btnH);
  }

  void draw() {
    noStroke(); fill(26); rect(x,y,w,h,10);
    fill(235); textAlign(CENTER,CENTER); textSize(24);
    text("Settings", x + w/2f, y + 30);
    textSize(15);

    fill(180);
    text("Decoder attivo: " + activeDecoder, x + w/2f, btnBinaural.y - 30);

    btnBinaural.draw(activeDecoder.equals("binaural"));
    btnSimple.draw(activeDecoder.equals("simple"));

    fill(180);
    text("Editor Decoder", x + w/2f, btnEditBinaural.y - 30);
    drawEditorButton(btnEditBinaural, "binaural");
    drawEditorButton(btnEditSimple, "simple");

    fill(150);
    textSize(12);
    text("Click su Binaural/Simple → /dj3d/switch_decoder\n"
       + "Editor Binaural/Simple: fa auto-switch se richiesto, poi apre editor.\n"
       + "Si può aprire solo l’editor del decoder attivo.", x + w/2f, btnEditSimple.y + btnEditSimple.h + 50);
    textSize(14);
  }

  void drawEditorButton(ToggleButton b, String dec) {
    boolean active = activeDecoder.equals(dec);
    if (active) {
      b.draw(b.state);
    } else {
      b.draw(false);
      noStroke(); fill(0,150); rect(b.x, b.y, b.w, b.h, 8);
      fill(230); textAlign(CENTER,CENTER); textSize(13);
      text((dec.equals("binaural") ? "Editor Binaural" : "Editor Simple") + "\n(auto switch)", b.x + b.w/2f, b.y + b.h/2f);
      textSize(14);
    }
  }

  void mousePressed(float mx,float my) {
    btnBinaural.mousePressed(mx,my);
    btnSimple.mousePressed(mx,my);
    btnEditBinaural.mousePressed(mx,my);
    btnEditSimple.mousePressed(mx,my);
  }

  void mouseDragged(float mx,float my) {}

  void mouseReleased(float mx,float my) {
    // Decoder
    if (btnBinaural.pressed && btnBinaural.contains(mx,my)) {
      if (!activeDecoder.equals("binaural") && osc != null) osc.switchDecoder("binaural");
    }
    btnBinaural.mouseReleased(mx,my);

    if (btnSimple.pressed && btnSimple.contains(mx,my)) {
      if (!activeDecoder.equals("simple") && osc != null) osc.switchDecoder("simple");
    }
    btnSimple.mouseReleased(mx,my);

    // Editor Binaural
    boolean eB = btnEditBinaural.pressed && btnEditBinaural.contains(mx,my);
    btnEditBinaural.mouseReleased(mx,my);
    if(eB) handleEditorPress("binaural", btnEditBinaural);

    // Editor Simple
    boolean eS = btnEditSimple.pressed && btnEditSimple.contains(mx,my);
    btnEditSimple.mouseReleased(mx,my);
    if(eS) handleEditorPress("simple", btnEditSimple);
  }

  void handleEditorPress(String target, ToggleButton btn) {
    if (osc == null) return;
    if (!activeDecoder.equals(target)) {
      pendingEditorAfterSwitch = target;
      btn.state = true;
      if (target.equals("binaural")) btnEditSimple.state = false; else btnEditBinaural.state = false;
      osc.switchDecoder(target);
      return;
    }
    // Già attivo
    if (!btn.state) {
      osc.decoderEditor(false);
      editorOpen = false;
      btnEditBinaural.state = false;
      btnEditSimple.state = false;
    } else {
      osc.decoderEditor(true);
      editorOpen = true;
      if (target.equals("binaural")) btnEditSimple.state = false; else btnEditBinaural.state = false;
    }
  }
}
