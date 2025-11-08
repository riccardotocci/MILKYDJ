// Main: gestione finestra, fullscreen, layout schermate, dual waveform, mixer centrale, file browser
// Aggiornato:
// - Waveform più basse (per dare più spazio ai deck)
// - Mixer centrale più stretto (midW ridotto) per allargare i deck
// - Area deck leggermente più alta

import java.io.File;
import processing.event.MouseEvent;
import beads.*;

final int SCREEN_MAIN  = 0;
final int SCREEN_MIXER = 1;
int currentScreen = SCREEN_MAIN;

PFont uiFont;

Deck deckA, deckB;
MixerScreen mixer;
AudioContext ac;
OscBridge osc;

Button btnMain, btnMixer;

WaveformStrip wfA, wfB;


MidiController midi;  // ← AGGIUNGI QUESTA

int lastMillis = 0;

// Fullscreen toggle state (fallback non‑macOS)
boolean isFullscreen = false;
int windowX = 50, windowY = 50; // posizione ricordata (facoltativa)
int windowW = 1860, windowH = 960; // dimensione default
int prevWindowX, prevWindowY, prevWindowW, prevWindowH;

// Zoom waveform
Slider zoomSlider;
// Range: 20..100 px/beat, iniziale 60
final float ZOOM_MIN_PPB = 20;
final float ZOOM_MAX_PPB = 100;

MixerCenterPanel centerPanel;
FileBrowserPanel fileBrowser;

void setup() {
  surface.setSize(windowW, windowH);
  surface.setLocation(windowX, windowY);
  makeWindowResizable(true);
  enableMacOSGreenFullscreen();

  surface.setTitle("DJ GUI (Waveforms + Decks + Mixer + File Browser)");
  smooth(4);
  uiFont = createFont("Inter", 14, true);
  textFont(uiFont);
 ac = new AudioContext();
 
 
 



  deckA = new Deck("Deck A", ac);
  deckB = new Deck("Deck B", ac);
  deckA.setPeer(deckB);
  deckB.setPeer(deckA);

  mixer = new MixerScreen(deckA, deckB, 4);

  btnMain  = new Button("Main");
  btnMixer = new Button("Mixer");

  wfA = new WaveformStrip("Deck A", deckA);
  wfB = new WaveformStrip("Deck B", deckB);

  zoomSlider = new Slider(false, 0.0);
  zoomSlider.setLabels("Zoom", "20", "100");
  float initialPPB = 60;
  float v = (initialPPB - ZOOM_MIN_PPB) / max(1, (ZOOM_MAX_PPB - ZOOM_MIN_PPB));
  zoomSlider.setValue(constrain(v, 0, 1));
  float ppb = map(zoomSlider.getValue(), 0, 1, ZOOM_MIN_PPB, ZOOM_MAX_PPB);
  wfA.setPixelsPerBeat(ppb);
  wfB.setPixelsPerBeat(ppb);

  centerPanel = new MixerCenterPanel(deckA, deckB);
  fileBrowser = new FileBrowserPanel(deckA, deckB);
  
  osc = new OscBridge(this);
  // Dì a OscBridge quali sono i riferimenti dei deck/pannelli (serve anche per mappare A/B)
  osc = new OscBridge(this);
  osc.setTargets(deckA, deckB);
  osc.setCenter(centerPanel);
  osc.setBrowser(fileBrowser);
  
  wfA.setOsc(osc);
wfB.setOsc(osc);
  
  // Istanzia il controller MIDI
  midi = new MidiController( deckA, deckB, centerPanel, fileBrowser);
  ac.start();
  lastMillis = millis();

}

void draw() {
  int now = millis();
  float dt = max(0, now - lastMillis) / 1000.0;
  lastMillis = now;

  background(20);

  float navH = 50;
  drawNavBar(navH);

  float contentY = navH;
  float contentH = height - navH;

  if (currentScreen == SCREEN_MAIN) {
    drawMainScreen(0, contentY, width, contentH, dt);
  } else {
    drawMixerScreen(0, contentY, width, contentH);
  }
}

void drawNavBar(float navH) {
  noStroke();
  fill(32);
  rect(0, 0, width, navH);

  float pad = 10;
  float btnW = 100;
  float btnH = navH - pad*2;

  btnMain.setBounds(pad, pad, btnW, btnH);
  btnMixer.setBounds(pad*2 + btnW, pad, btnW, btnH);

  btnMain.draw(currentScreen == SCREEN_MAIN);
  btnMixer.draw(currentScreen == SCREEN_MIXER);

  float zW = 260;
  float zH = 16;
  float zX = width - pad - zW;
  float zY = (navH - zH) / 2.0;
  zoomSlider.setBounds(zX, zY, zW, zH);
  zoomSlider.draw();

  float ppb = map(zoomSlider.getValue(), 0, 1, ZOOM_MIN_PPB, ZOOM_MAX_PPB);
  wfA.setPixelsPerBeat(ppb);
  wfB.setPixelsPerBeat(ppb);

  fill(220);
  textAlign(RIGHT, CENTER);
  text("Main: Dual Waveforms + Decks + Center Mixer + File Browser  |  F: Fullscreen", zX - 12, navH/2);
}

void drawMainScreen(float x, float y, float w, float h, float dt) {
  float pad = 16;
  float gapWave = 6; // più compatte

  deckA.updateTransport(dt);
  deckB.updateTransport(dt);

  // Waveform più basse per liberare spazio ai deck
  float waveH = constrain(h * 0.14, 30, 70);

  float wfAX = x + pad;
  float wfAY = y + pad;
  float wfAW = w - pad*2;
  float wfAH = waveH;

  float wfBX = x + pad;
  float wfBY = wfAY + wfAH + gapWave;
  float wfBW = wfAW;
  float wfBH = waveH;

  wfA.setBounds(wfAX, wfAY, wfAW, wfAH);
  wfB.setBounds(wfBX, wfBY, wfBW, wfBH);
  wfA.update(dt);
  wfB.update(dt);
  wfA.draw();
  wfB.draw();

  float topAfterWavesY = wfBY + wfBH + pad;

  // File browser invariato
  float browserH = constrain(h * 0.32, 200, 380);

  // Area controlli: un po' più alta per ingrandire i deck
  float controlsY = topAfterWavesY;
  float controlsH = max(170, (y + h) - controlsY - pad - browserH - pad);

  float colGap = 16;
  // Mixer centrale più stretto per allargare i deck
  float midW = constrain(w * 0.18, 220, 300);
  float sideW = (w - pad*2 - colGap*2 - midW) / 2.0;

  float leftX  = x + pad;
  float midX   = leftX + sideW + colGap;
  float rightX = midX + midW + colGap;

  noStroke();
  fill(28);
  rect(leftX, controlsY, sideW, controlsH, 10);
  rect(midX, controlsY, midW, controlsH, 10);
  rect(rightX, controlsY, sideW, controlsH, 10);

  deckA.updateLayout(leftX, controlsY, sideW, controlsH);
  deckB.updateLayout(rightX, controlsY, sideW, controlsH);
  centerPanel.updateLayout(midX, controlsY, midW, controlsH);

  deckA.drawControls();
  deckB.drawControls();
  centerPanel.draw();

  float browserY = controlsY + controlsH + pad;
  float browserX = x + pad;
  float browserW = w - pad*2;

  fileBrowser.updateLayout(browserX, browserY, browserW, browserH);
  fileBrowser.draw();

  drawAnalysisBadges(deckA, wfAX, wfAY, wfAW);
  drawAnalysisBadges(deckB, wfBX, wfBY, wfBW);
}

void drawMixerScreen(float x, float y, float w, float h) {
  mixer.updateLayout(x, y, w, h);
  mixer.draw();
}

void drawAnalysisBadges(Deck d, float ax, float ay, float aw) {
  String msg = "";
  if (d.isAnalyzing) msg = "Analisi in corso...";
  else if (d.analysisError != null && d.analysisError.length() > 0) msg = "Analisi fallita: " + d.analysisError;
  else if (d.analysis != null) msg = "BPM: " + nf(d.analysis.bpm, 0, 1) + " • Beats: " + d.analysis.beats.size();
  else msg = "Nessuna analisi • Carica un file WAV/AIFF";

  float th = 22;
  float tw = textWidth(msg) + 16;
  float bx = ax + 10;
  float by = ay + 10;

  noStroke();
  fill(40, 40, 40, 210);
  rect(bx, by, tw, th, 6);
  fill(220);
  textAlign(LEFT, CENTER);
  text(msg, bx + 8, by + th/2);
}

// ——————————————————————————
// Fullscreen (macOS green button + fallback tasto F)
// ——————————————————————————

boolean isMac() {
  String os = System.getProperty("os.name");
  return os != null && os.toLowerCase().contains("mac");
}

// Ottieni la Window AWT dalla surface
java.awt.Window getWindowFromSurface() {
  Object nat = surface.getNative();
  try {
    java.lang.reflect.Method m = nat.getClass().getMethod("getFrame");
    Object frame = m.invoke(nat);
    if (frame instanceof java.awt.Window) return (java.awt.Window) frame;
  } catch (Exception ignore) {}
  if (nat instanceof java.awt.Component) {
    return javax.swing.SwingUtilities.getWindowAncestor((java.awt.Component) nat);
  }
  return null;
}

void makeWindowResizable(boolean res) {
  java.awt.Window w = getWindowFromSurface();
  if (w instanceof java.awt.Frame) {
    ((java.awt.Frame) w).setResizable(res);
  }
}

void enableMacOSGreenFullscreen() {
  if (!isMac()) return;
  java.awt.Window w = getWindowFromSurface();
  if (w == null) return;
  try {
    Class<?> util = Class.forName("com.apple.eawt.FullScreenUtilities");
    java.lang.reflect.Method setCanFS =
      util.getMethod("setWindowCanFullScreen", java.awt.Window.class, boolean.class);
    setCanFS.invoke(null, w, true);
  } catch (Exception ignore) {}
  try {
    if (w instanceof javax.swing.JFrame) {
      javax.swing.JFrame jf = (javax.swing.JFrame) w;
      jf.getRootPane().putClientProperty("apple.awt.fullscreenable", true);
    }
  } catch (Exception ignore) {}
}

void toggleFullscreen() {
  java.awt.Window w = getWindowFromSurface();
  if (w == null) return;

  if (isMac()) {
    try {
      Class<?> appClass = Class.forName("com.apple.eawt.Application");
      Object app = appClass.getMethod("getApplication").invoke(null);
      appClass.getMethod("requestToggleFullScreen", java.awt.Window.class).invoke(app, w);
      return;
    } catch (Exception e) {}
  }
  if (w instanceof java.awt.Frame) {
    java.awt.Frame f = (java.awt.Frame) w;
    if (!isFullscreen) {
      prevWindowX = w.getX(); prevWindowY = w.getY();
      prevWindowW = w.getWidth(); prevWindowH = w.getHeight();
      f.setExtendedState(java.awt.Frame.MAXIMIZED_BOTH);
      isFullscreen = true;
    } else {
      f.setExtendedState(java.awt.Frame.NORMAL);
      surface.setSize(prevWindowW, prevWindowH);
      surface.setLocation(prevWindowX, prevWindowY);
      isFullscreen = false;
    }
  }
}

void mousePressed() {
  if (btnMain.contains(mouseX, mouseY)) { currentScreen = SCREEN_MAIN; return; }
  if (btnMixer.contains(mouseX, mouseY)) { currentScreen = SCREEN_MIXER; return; }
  if (zoomSlider.contains(mouseX, mouseY)) { zoomSlider.mousePressed(mouseX, mouseY); return; }

  if (currentScreen == SCREEN_MAIN) {
    wfA.mousePressed(mouseX, mouseY);
    wfB.mousePressed(mouseX, mouseY);
  }
  
  if (currentScreen == SCREEN_MAIN) {
    deckA.mousePressed(mouseX, mouseY);
    deckB.mousePressed(mouseX, mouseY);
    centerPanel.mousePressed(mouseX, mouseY);
    fileBrowser.mousePressed(mouseX, mouseY);
  } else {
    mixer.mousePressed(mouseX, mouseY);
  }
}

void mouseDragged() {
  if (zoomSlider.dragging) { zoomSlider.mouseDragged(mouseX, mouseY); return; }
  if (currentScreen == SCREEN_MAIN) {
    wfA.mouseDragged(mouseX, mouseY);
    wfB.mouseDragged(mouseX, mouseY);
  }
  
  if (currentScreen == SCREEN_MAIN) {
    deckA.mouseDragged(mouseX, mouseY);
    deckB.mouseDragged(mouseX, mouseY);
    centerPanel.mouseDragged(mouseX, mouseY);
    fileBrowser.mouseDragged(mouseX, mouseY);
  } else {
    mixer.mouseDragged(mouseX, mouseY);
  }
}

void mouseReleased() {
  zoomSlider.mouseReleased(mouseX, mouseY);
  if (currentScreen == SCREEN_MAIN) {
    wfA.mouseReleased(mouseX, mouseY);
    wfB.mouseReleased(mouseX, mouseY);
  }
  if (currentScreen == SCREEN_MAIN) {
    deckA.mouseReleased(mouseX, mouseY);
    deckB.mouseReleased(mouseX, mouseY);
    centerPanel.mouseReleased(mouseX, mouseY);
    fileBrowser.mouseReleased(mouseX, mouseY);
  } else {
    mixer.mouseReleased(mouseX, mouseY);
  }
}

void mouseWheel(MouseEvent event) {
  if (currentScreen == SCREEN_MAIN) fileBrowser.mouseWheel(event.getCount());
}

void keyPressed() {
  if (key == 'm' || key == 'M') {
    currentScreen = (currentScreen == SCREEN_MAIN) ? SCREEN_MIXER : SCREEN_MAIN;
  } else if (key == 'f' || key == 'F') {
    toggleFullscreen();
  }
}

void stop() {
  if (midi != null) midi.dispose();
  super.stop();
}
