// Slider generico 0..1 (verticale o orizzontale)
// Interazione: trascinamento
// Disegno: track scuro, maniglia chiara, etichette opzionali

class Slider {
  boolean vertical;
  float value; // 0..1
  boolean dragging = false;

  float x, y, w, h;

  String label = "";
  String minLabel = "";
  String maxLabel = "";

  Slider(boolean vertical, double initial) {
    this.vertical = vertical;
    this.value = constrain((float)initial, 0, 1);
  }

  void setLabels(String label, String minLabel, String maxLabel) {
    this.label = label; this.minLabel = minLabel; this.maxLabel = maxLabel;
  }

  void setBounds(float x, float y, float w, float h) {
    this.x = x; this.y = y; this.w = w; this.h = h;
  }

  void setValue(float v) { value = constrain(v, 0, 1); }
  float getValue() { return value; }

  boolean contains(float mx, float my) {
    return mx >= x && mx <= x + w && my >= y && my <= y + h;
  }

  void mousePressed(float mx, float my) {
    if (contains(mx, my)) {
      dragging = true;
      updateValueFromMouse(mx, my);
    }
  }

  void mouseDragged(float mx, float my) {
    if (!dragging) return;
    updateValueFromMouse(mx, my);
  }

  void mouseReleased(float mx, float my) {
    dragging = false;
  }

  void updateValueFromMouse(float mx, float my) {
    if (vertical) {
      float t = 1.0 - (my - y) / max(1, h);
      value = constrain(t, 0, 1);
    } else {
      float t = (mx - x) / max(1, w);
      value = constrain(t, 0, 1);
    }
  }

  void draw() {
    noStroke();
    fill(36);
    rect(x, y, w, h, 4);

    if (vertical) {
      float fy = y + (1.0 - value) * h;
      float fh = 8;
      fill(200);
      rect(x + 2, fy - fh/2, w - 4, fh, 3);

      if (label.length() > 0) {
        fill(220);
        textAlign(CENTER, BOTTOM);
        text(label, x + w/2, y - 4);
        textAlign(LEFT, CENTER);
        textSize(10);
        fill(180);
        text(minLabel, x + w + 6, y + h - 6);
        text(maxLabel, x + w + 6, y + 6);
        textSize(14);
      }
    } else {
      float fx = x + value * w;
      float fw = 10;
      fill(200);
      rect(fx - fw/2, y + 2, fw, h - 4, 3);

      if (label.length() > 0) {
        fill(220);
        textAlign(LEFT, BOTTOM);
        text(label, x, y - 4);
        textAlign(RIGHT, CENTER);
        textSize(10);
        fill(180);
        text(minLabel, x - 6, y + h + 10);
        text(maxLabel, x + w + 6, y + h + 10);
        textSize(14);
      }
    }
  }
}
