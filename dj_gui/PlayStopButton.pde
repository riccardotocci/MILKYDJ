// PlayStopButton: pulsante con icona Play/Stop

class PlayStopButton extends Button {
  boolean playing = false;

  PlayStopButton() { super(""); }

  void setPlaying(boolean p) { playing = p; }
  boolean getPlaying() { return playing; }

  @Override
  void mouseReleased(float mx, float my) {
    if (pressed && contains(mx, my)) {
      playing = !playing;
    }
    pressed = false;
  }

  @Override
  void draw(boolean active) {
    boolean hover = contains(mouseX, mouseY);
    stroke(60);
    strokeWeight(1);
    if (playing) {
      fill(80, 160, 110);
    } else if (pressed) {
      fill(60);
    } else if (hover) {
      fill(50);
    } else {
      fill(40);
    }
    rect(x, y, w, h, 8);

    pushMatrix();
    translate(x + w/2, y + h/2);
    noStroke();
    fill(240);
    if (!playing) {
      float s = min(w, h) * 0.36;
      triangle(-s*0.4, -s*0.6, -s*0.4, s*0.6, s*0.7, 0);
    } else {
      float s = min(w, h) * 0.42;
      rectMode(CENTER);
      rect(-s*0.25, 0, s*0.25, s*0.8, 2);
      rect( s*0.25, 0, s*0.25, s*0.8, 2);
      rectMode(CORNER);
    }
    popMatrix();
  }
}
