// Knob (manopola) 0..1 con etichetta e colore accent
// Interazione: trascinamento verticale

class Knob {
  float cx, cy;
  float r;
  float value = 0.5;
  boolean dragging = false;
  float dragStartY, dragStartVal;

  String label = "";
  String minLabel = "";
  String maxLabel = "";

  int accentColor = color(90, 200, 255);

  void setBounds(float cx, float cy, float diameter) {
    this.cx = cx;
    this.cy = cy;
    this.r = max(10, diameter/2.0);
  }

  void setLabels(String label, String minLabel, String maxLabel) {
    this.label = label;
    this.minLabel = minLabel;
    this.maxLabel = maxLabel;
  }

  void setAccentColor(int c) { this.accentColor = c; }

  void setValue(float v) { value = constrain(v, 0, 1); }
  float getValue() { return value; }

  boolean contains(float mx, float my) {
    return dist(mx, my, cx, cy) <= r + 6;
  }

  void mousePressed(float mx, float my) {
    if (contains(mx, my)) {
      dragging = true;
      dragStartY = my;
      dragStartVal = value;
    }
  }

  void mouseDragged(float mx, float my) {
    if (!dragging) return;
    float dy = my - dragStartY;
    float v = dragStartVal - dy * 0.006;
    value = constrain(v, 0, 1);
  }

  void mouseReleased(float mx, float my) {
    dragging = false;
  }

  void draw() {
    noStroke();
    fill(34);
    circle(cx, cy, r*2);

    stroke(70);
    strokeWeight(2);
    noFill();
    circle(cx, cy, r*2 - 2);

    float a0 = PI*0.75;
    float a1 = PI*2.25;

    stroke(70);
    strokeWeight(4);
    arc(cx, cy, r*1.6, r*1.6, a0, a1);

    stroke(accentColor);
    strokeWeight(4);
    float av = lerp(a0, a1, value);
    arc(cx, cy, r*1.6, r*1.6, a0, av);

    float px = cx + cos(av) * (r*0.9);
    float py = cy + sin(av) * (r*0.9);
    stroke(240);
    strokeWeight(4);
    line(cx, cy, px, py);
    stroke(accentColor);
    strokeWeight(2);
    line(cx, cy, px, py);

    noStroke();
    fill(22);
    circle(cx, cy, r*0.5);

    fill(220);
    textAlign(CENTER, TOP);
    textSize(11);
    text(label, cx, cy + r + 5);

    textAlign(CENTER, BOTTOM);
    String valTxt = nf(value*100, 0, 0) + "%";
    textSize(10);
    text(valTxt, cx, cy - r - 4);
    textSize(14);
  }
}
