// EncoderChannelPanel.pde
// Pannello lista canali encoder per un singolo deck.
// - Mostra i canali in ordine di indice.
// - Per ogni canale: nome, meter verticale, pulsante "Editor" toggle.
// - I livelli vengono aggiornati via OscBridge (getChannelsForDeck).
// - Scroll semplice se i canali eccedono l’altezza.

class EncoderChannelPanel {
  String deckId;              // "A" | "B"
  OscBridge osc;

  float x, y, w, h;

  int rowH = 34;
  int headerH = 36;
  int pad = 10;

  float scroll;               // 0..1
  boolean draggingScroll = false;
  float scrollBarX, scrollBarY, scrollBarW, scrollBarH;
  float scrollKnobY;

  EncoderChannelPanel(String deckId, OscBridge osc) {
    this.deckId = deckId;
    this.osc = osc;
  }

  void setBounds(float x, float y, float w, float h) {
    this.x = x; this.y = y; this.w = w; this.h = h;
    // area scrollbar stretta a destra
    scrollBarW = 10;
    scrollBarX = x + w - scrollBarW - 4;
    scrollBarY = y + headerH + 4;
    scrollBarH = h - headerH - 8;
  }

  void draw() {
    noStroke();
    fill(26);
    rect(x, y, w, h, 10);

    // Header
    fill(230);
    textAlign(LEFT, CENTER);
    textSize(16);
    text("Deck " + deckId + " Encoders", x + pad, y + headerH/2f);

    textSize(13);
    fill(150);
    textAlign(RIGHT, CENTER);
    int count = 0;
    if (osc != null) {
      EncoderChannelInfo[] infos = osc.getChannelsForDeck(deckId);
      if (infos != null) count = infos.length;
    }
    text(count + " ch", x + w - pad - scrollBarW - 6, y + headerH/2f);
    textSize(14);

    // Lista
    EncoderChannelInfo[] chans = (osc != null) ? osc.getChannelsForDeck(deckId) : null;
    if (chans == null || chans.length == 0) {
      fill(160);
      textAlign(CENTER, CENTER);
      text("Nessun canale (carica un file)", x + w/2f, y + headerH + (h - headerH)/2f);
      return;
    }

    int visibleRows = max(1, floor((h - headerH - pad*2) / rowH));
    int total = chans.length;
    int maxOffset = max(0, total - visibleRows);
    int offset = (maxOffset == 0) ? 0 : round(scroll * maxOffset);

    float listY = y + headerH + pad;
    for (int i = 0; i < visibleRows; i++) {
      int idx = offset + i;
      if (idx >= total) break;
      float ry = listY + i * rowH;
      drawRow(idx, chans[idx], ry);
    }

    drawScrollbar(total, visibleRows);
  }

  void drawRow(int idx, EncoderChannelInfo info, float ry) {
    float rx = x + pad;
    float rw = w - pad*2 - scrollBarW - 8;

    // Fondo riga
    noStroke();
    fill((idx % 2 == 0) ? 34 : 30);
    rect(rx, ry, rw, rowH - 4, 6);

    // Nome
    fill(220);
    textAlign(LEFT, CENTER);
    textSize(13);
    text(info.name, rx + 8, ry + (rowH - 4)/2f);
    textSize(14);

    // Meter (verticale piccolo)
    float meterW = 20;
    float meterH = rowH - 12;
    float meterX = rx + rw - 8 - meterW - 72;  // spazio prima del pulsante Editor
    float meterY = ry + 6;

    drawMeter(meterX, meterY, meterW, meterH, info.level);

    // Pulsante Editor
    float btnW = 60;
    float btnH = rowH - 10;
    float btnX = rx + rw - 8 - btnW;
    float btnY = ry + 5;

    boolean hover = mouseX >= btnX && mouseX <= btnX + btnW && mouseY >= btnY && mouseY <= btnY + btnH;
    noStroke();
    if (info.editorOpen) fill(80, 150, 230);
    else if (hover) fill(52);
    else fill(44);
    rect(btnX, btnY, btnW, btnH, 6);
    fill(230);
    textAlign(CENTER, CENTER);
    text(info.editorOpen ? "Close" : "Editor", btnX + btnW/2f, btnY + btnH/2f);

    // Salva bounds nel ChannelInfo per hit-test
    info.btnX = btnX; info.btnY = btnY; info.btnW = btnW; info.btnH = btnH;
  }

  void drawMeter(float mx, float my, float mw, float mh, float level) {
    noStroke();
    fill(22);
    rect(mx, my, mw, mh, 4);
    float L = constrain(level, 0, 1);
    int c;
    if (L < 0.7) c = lerpColor(color(70,210,90), color(220,220,80), L/0.7);
    else c = lerpColor(color(220,220,80), color(230,70,70), (L-0.7)/0.3);
    float barH = mh * L;
    noStroke();
    fill(c);
    rect(mx + 3, my + mh - barH - 3, mw - 6, barH, 3);
  }

  void drawScrollbar(int total, int visible) {
    if (total <= visible) return;
    noStroke();
    fill(36);
    rect(scrollBarX, scrollBarY, scrollBarW, scrollBarH, 4);

    float frac = (float)visible / total;
    float knobH = max(28, scrollBarH * frac);
    float track = scrollBarH - knobH;
    float knobY = scrollBarY + track * scroll;
    fill(90);
    rect(scrollBarX + 1, knobY, scrollBarW - 2, knobH, 4);

    scrollKnobY = knobY;
  }

  boolean contains(float mx, float my) {
    return mx >= x && mx <= x + w && my >= y && my <= y + h;
  }

  void mousePressed(float mx, float my) {
    if (!contains(mx, my)) return;
    if (totalScrollable()) {
      float knobH = computeKnobH();
      if (mx >= scrollBarX && mx <= scrollBarX + scrollBarW &&
          my >= scrollKnobY && my <= scrollKnobY + knobH) {
        draggingScroll = true;
        return;
      }
    }

    EncoderChannelInfo[] chans = osc.getChannelsForDeck(deckId);
    if (chans == null) return;
    int visibleRows = max(1, floor((h - headerH - pad*2) / rowH));
    int maxOffset = max(0, chans.length - visibleRows);
    int offset = (maxOffset == 0) ? 0 : round(scroll * maxOffset);

    float listY = y + headerH + pad;

    for (int i = 0; i < visibleRows; i++) {
      int idx = offset + i;
      if (idx >= chans.length) break;
      float ry = listY + i * rowH;
      EncoderChannelInfo info = chans[idx];
      // Hit test editor button
      if (mx >= info.btnX && mx <= info.btnX + info.btnW &&
          my >= info.btnY && my <= info.btnY + info.btnH) {
        toggleEditor(idx, info);
        break;
      }
    }
  }

  void mouseDragged(float mx, float my) {
    if (draggingScroll) {
      float knobH = computeKnobH();
      float track = scrollBarH - knobH;
      float ny = constrain(my - scrollBarY - knobH/2f, 0, track);
      scroll = (track <= 0) ? 0 : ny / track;
    }
  }

  void mouseReleased(float mx, float my) {
    draggingScroll = false;
  }

  boolean totalScrollable() {
    EncoderChannelInfo[] chans = osc.getChannelsForDeck(deckId);
    if (chans == null) return false;
    int visibleRows = max(1, floor((h - headerH - pad*2) / rowH));
    return chans.length > visibleRows;
  }

  float computeKnobH() {
    EncoderChannelInfo[] chans = osc.getChannelsForDeck(deckId);
    int total = (chans == null) ? 0 : chans.length;
    int visibleRows = max(1, floor((h - headerH - pad*2) / rowH));
    float frac = (float)visibleRows / max(1, total);
    return max(28, scrollBarH * frac);
  }

  void toggleEditor(int idx, EncoderChannelInfo info) {
    boolean newState = !info.editorOpen;
    info.editorOpen = newState;
    if (osc != null) {
      Deck d = deckId.equals("A") ? osc.deckA : osc.deckB;
      osc.deckEncoderEditor(d, idx, newState);
    }
  }
}
