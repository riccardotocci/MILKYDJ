// ToggleButton: pulsante toggle con stato booleano

class ToggleButton extends Button {
  boolean state = false;

  ToggleButton(String label, boolean initial) {
    super(label);
    state = initial;
  }

  @Override
  void mouseReleased(float mx, float my) {
    if (pressed && contains(mx, my)) {
      state = !state;
    }
    pressed = false;
  }

  @Override
  void draw(boolean active) {
    boolean hover = contains(mouseX, mouseY);
    stroke(60);
    strokeWeight(1);
    if (state) {
      fill(80, 160, 110);
    } else if (pressed) {
      fill(60);
    } else if (hover) {
      fill(50);
    } else {
      fill(40);
    }
    rect(x, y, w, h, 8);

    fill(230);
    textAlign(CENTER, CENTER);
    text(label, x + w/2, y + h/2);
  }
}
