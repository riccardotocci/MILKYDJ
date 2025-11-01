// MixerScreen: schermata alternativa che mostra solo il MixerCenterPanel su tutta l'area

class MixerScreen {
  MixerCenterPanel panel;

  MixerScreen(Deck a, Deck b, int n) {
    panel = new MixerCenterPanel(a, b);
  }

  void updateLayout(float x, float y, float w, float h) {
    panel.updateLayout(x, y, w, h);
  }

  void draw() {
    panel.draw();
  }

  void mousePressed(float mx, float my) { panel.mousePressed(mx, my); }
  void mouseDragged(float mx, float my) { panel.mouseDragged(mx, my); }
  void mouseReleased(float mx, float my) { panel.mouseReleased(mx, my); }
}
