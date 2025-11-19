// MixerScreen: nuovo layout — due pannelli (Deck A / Deck B) con i canali encoder.
// Rimuove il vecchio MixerCenterPanel dalla vista Mixer (rimane usato altrove nel MAIN).
// Usa EncoderChannelPanel per deck A e B.

class MixerScreen {
  EncoderChannelPanel panelA;
  EncoderChannelPanel panelB;
  OscBridge osc;

  float x, y, w, h;

  MixerScreen(Deck a, Deck b, OscBridge osc) {
    this.osc = osc;
    panelA = new EncoderChannelPanel("A", osc);
    panelB = new EncoderChannelPanel("B", osc);
  }

  void updateLayout(float x, float y, float w, float h) {
    this.x = x; this.y = y; this.w = w; this.h = h;

    float pad = 16;
    float gap = 20;
    float panelW = (w - pad*2 - gap) * 0.5;

    panelA.setBounds(x + pad, y + pad, panelW, h - pad*2);
    panelB.setBounds(x + pad + panelW + gap, y + pad, panelW, h - pad*2);
  }

  void draw() {
    panelA.draw();
    panelB.draw();
  }

  void mousePressed(float mx, float my) {
    panelA.mousePressed(mx, my);
    panelB.mousePressed(mx, my);
  }
  void mouseDragged(float mx, float my) {
    panelA.mouseDragged(mx, my);
    panelB.mouseDragged(mx, my);
  }
  void mouseReleased(float mx, float my) {
    panelA.mouseReleased(mx, my);
    panelB.mouseReleased(mx, my);
  }
}
