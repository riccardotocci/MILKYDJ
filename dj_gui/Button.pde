// Button: pulsante base con stato pressed, disegno semplice

class Button {
  String label;
  float x, y, w, h;
  boolean pressed = false;

  Button(String label) {
    this.label = label;
  }

  void setBounds(float x, float y, float w, float h) {
    this.x = x; this.y = y; this.w = w; this.h = h;
  }

  boolean contains(float mx, float my) {
    return mx >= x && mx <= x + w && my >= y && my <= y + h;
  }

  void mousePressed(float mx, float my) {
    if (contains(mx, my)) pressed = true;
  }

  void mouseReleased(float mx, float my) {
    pressed = false;
  }

  // DEFAULT no-arg overload to support calls like playBtn.draw()
  void draw() {
    draw(false);
  }

  void draw(boolean active) {
    boolean hover = contains(mouseX, mouseY);
    stroke(60);
    strokeWeight(1);
    if (active) {
      fill(70, 110, 170);
    } else if (pressed) {
      fill(60);
    } else if (hover) {
      fill(50);
    } else {
      fill(40);
    }
    rect(x, y, w, h, 8);

    fill(active ? color(240) : color(220));
    textAlign(CENTER, CENTER);
    text(label, x + w/2, y + h/2);
  }
}
