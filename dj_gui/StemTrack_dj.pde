// StemTrack: slider volume ORIZZONTALE a tutta larghezza, mute piccolo, icona grande

class StemTrack {
  String name;

  Slider volume;         // orizzontale
  boolean muted = false;

  float x, y, w, h;

  float pad = 4;
  float sliderH = 14;
  float muteS   = 14;

  float iconX, iconY, iconW, iconH;
  float sliderX, sliderY, sliderW;
  float muteX, muteY;

  PImage icon = null;
  boolean triedLoadIcon = false;

  boolean mutePressed = false;

  StemTrack(String name) {
    this.name = name;
    volume = new Slider(false, 0.9); // orizzontale
    volume.setLabels("", "", "");
  }

  void setBounds(float x, float y, float w, float h) {
    this.x = x; this.y = y; this.w = w; this.h = h;

    sliderH = constrain(round(max(12, h * 0.18)), 12, 16);
    muteS   = constrain(round(max(12, h * 0.22)), 12, 18);

    float sliderTop = y + h - pad - muteS - pad - sliderH;
    sliderX = x + pad;
    sliderY = sliderTop;
    sliderW = max(10, w - pad*2);
    volume.setBounds(sliderX, sliderY, sliderW, sliderH);

    muteX = x + w - pad - muteS;
    muteY = y + h - pad - muteS;

    iconX = x + pad;
    iconY = y + pad;
    iconW = max(10, w - pad*2);
    iconH = max(10, sliderY - pad - iconY);
  }

  void draw() {
    noStroke(); fill(28); rect(x, y, w, h, 6);
    drawIconBox();
    volume.draw();
    drawMuteButton();
  }

  void drawIconBox() {
    stroke(60); strokeWeight(1.5); fill(22); rect(iconX, iconY, iconW, iconH, 6);
    ensureIconLoaded();
    if (icon != null) {
      float availW = iconW - pad*2, availH = iconH - pad*2;
      float sx = icon.width, sy = icon.height;
      float scale = min(availW / sx, availH / sy);
      float dw = sx * scale, dh = sy * scale;
      float dx = iconX + (iconW - dw)/2.0, dy = iconY + (iconH - dh)/2.0;
      noStroke(); image(icon, dx, dy, dw, dh);
    } else {
      drawIconPlaceholder(iconX, iconY, iconW, iconH);
    }
    if (muted) { noStroke(); fill(0, 150); rect(iconX, iconY, iconW, iconH, 6); drawMuteGlyph(iconX + iconW/2, iconY + iconH/2, min(iconW, iconH) * 0.25); }
  }

  void ensureIconLoaded() {
    if (triedLoadIcon || icon != null) return; triedLoadIcon = true;
    String key = name.toLowerCase(); String file = null;
    if (key.equals("drums")) file = "stems/drums.png";
    else if (key.equals("bass")) file = "stems/bass.png";
    else if (key.equals("instruments")) file = "stems/instruments.png";
    else if (key.equals("vocals")) file = "stems/vocals.png";
    if (file != null) { try { icon = loadImage(file); } catch (Exception e) { icon = null; } }
  }

  void drawIconPlaceholder(float bx, float by, float bw, float bh) {
    float cx = bx + bw/2f, cy = by + bh/2f, r = min(bw, bh) * 0.36f;
    noStroke(); fill(46); circle(cx, cy, r*2);
    fill(180);
    if (name.equals("Drums")) { rectMode(CENTER); rect(cx, cy + r*0.2, r*1.2, r*0.28, 4); circle(cx - r*0.55, cy - r*0.1, r*0.34); circle(cx + r*0.55, cy - r*0.24, r*0.26); rectMode(CORNER); }
    else if (name.equals("Bass")) { beginShape(); vertex(cx, cy - r); vertex(cx - r*0.85, cy + r*0.8); vertex(cx + r*0.85, cy + r*0.8); endShape(CLOSE); }
    else if (name.equals("Instruments")) { float bars = 5, barW = r*0.28, gap  = r*0.12, startX = cx - ((bars*barW + (bars-1)*gap)/2f); for (int i=0;i<bars;i++){ float hh=r*(0.6+0.4*(i%2)); rect(startX+i*(barW+gap), cy+r*0.6-hh, barW, hh);} }
    else if (name.equals("Vocals")) { noFill(); stroke(180); strokeWeight(2); arc(cx, cy, r*1.5, r*1.2, PI*0.2, PI*0.8); arc(cx, cy, r*1.1, r*0.9, PI*0.3, PI*0.7); noStroke(); }
  }

  void drawMuteButton() {
    boolean hover = containsMute(mouseX, mouseY);
    stroke(70); strokeWeight(1);
    if (muted) fill(200, 70, 70);
    else if (mutePressed) fill(60);
    else if (hover) fill(50);
    else fill(40);
    rect(muteX, muteY, muteS, muteS, 3);
    drawSpeakerGlyph(muteX + muteS/2f, muteY + muteS/2f, muteS * 0.65f, muted);
  }

  void drawSpeakerGlyph(float cx, float cy, float s, boolean crossed) {
    float w = s*0.55f, h = s*0.45f;
    noStroke(); fill(230);
    triangle(cx - w*0.55f, cy - h*0.5f, cx - w*0.55f, cy + h*0.5f, cx + w*0.35f, cy);
    rectMode(CENTER); rect(cx - w*0.8f, cy, w*0.35f, h*0.9f, 1.5f); rectMode(CORNER);
    if (crossed) { stroke(30); strokeWeight(3); line(cx - s*0.45f, cy + s*0.45f, cx + s*0.45f, cy - s*0.45f); stroke(255,230,230); strokeWeight(1.5); line(cx - s*0.45f, cy + s*0.45f, cx + s*0.45f, cy - s*0.45f); }
  }

  void drawMuteGlyph(float cx, float cy, float s) { drawSpeakerGlyph(cx, cy, s, true); }

  boolean containsMute(float mx, float my) { return mx >= muteX && mx <= muteX + muteS && my >= muteY && my <= muteY + muteS; }

  void mousePressed(float mx, float my) {
    if (containsMute(mx, my)) mutePressed = true;
    else if (mx >= sliderX && mx <= sliderX + sliderW && my >= sliderY && my <= sliderY + sliderH) volume.mousePressed(mx, my);
  }

  void mouseDragged(float mx, float my) { if (volume.dragging) volume.mouseDragged(mx, my); }

  void mouseReleased(float mx, float my) {
    if (mutePressed) { if (containsMute(mx, my)) muted = !muted; mutePressed = false; }
    volume.mouseReleased(mx, my);
  }
}
