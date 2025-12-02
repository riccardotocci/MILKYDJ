/**
 * Main.pde
 *
 * Schermo principale Processing per MILKY_DJ con tre schermate:
 *  - MAIN   (Waveforms + Decks + Mixer + File Browser)
 *  - MIXER  (Mixer isolato fullscreen)
 *  - SETTINGS (Decoder + Editor Binaural/Simple)
 *
 * Tasti rapidi:
 *   M → cicla MAIN/MIXER
 *   S → vai a SETTINGS
 *   F → fullscreen toggle
 */

import java.io.File;
import processing.event.MouseEvent;
import beads.*;

final int SCREEN_MAIN    = 0;
final int SCREEN_MIXER   = 1;
final int SCREEN_SETTINGS= 2;
int currentScreen = SCREEN_MAIN;

PFont uiFont;

// Audio / Core
AudioContext ac;
OscBridge osc;

// Decks & UI components
Deck deckA, deckB;
MixerCenterPanel centerPanel;
FileBrowserPanel fileBrowser;
MixerScreen mixer;
SettingsScreen settings;

// Waveforms
WaveformStrip wfA, wfB;

// MIDI controller
MidiController_Hercules midi;

// Navigation buttons
Button btnMain, btnMixer, btnSettings;

// Zoom slider
Slider zoomSlider;
final float ZOOM_MIN_PPB = 20;
final float ZOOM_MAX_PPB = 100;

// Time tracking
int lastMillis = 0;

// Fullscreen state
boolean isFullscreen = false;
int windowX = 50, windowY = 50;
int windowW = 1860, windowH = 960;
int prevWindowX, prevWindowY, prevWindowW, prevWindowH;

void setup() {
  surface.setSize(windowW, windowH);
  surface.setLocation(windowX, windowY);
  makeWindowResizable(true);
  enableMacOSGreenFullscreen();

  surface.setTitle("MILKY_DJ GUI");
  smooth(4);

  uiFont = createFont("Inter", 14, true);
  textFont(uiFont);

  ac = new AudioContext();

  // Decks
  deckA = new Deck("Deck A", ac);
  deckB = new Deck("Deck B", ac);
  deckA.setPeer(deckB);
  deckB.setPeer(deckA);
  
  osc = new OscBridge(this);

  centerPanel = new MixerCenterPanel(deckA, deckB);
  fileBrowser = new FileBrowserPanel(deckA, deckB);
  mixer = new MixerScreen(deckA, deckB, osc);
   settings = new SettingsScreen(osc);

  // Waveforms
  wfA = new WaveformStrip("Deck A", deckA);
  wfB = new WaveformStrip("Deck B", deckB);
  
  // Colori waveform: A blu, B rossa
  wfA.setWaveColor(color(90, 200, 255));
  wfB.setWaveColor(color(255, 110, 110));

  // Zoom
  zoomSlider = new Slider(false, 0.0);
  zoomSlider.setLabels("Zoom", "20", "100");
  float initialPPB = 60;
  float v = (initialPPB - ZOOM_MIN_PPB) / max(1, (ZOOM_MAX_PPB - ZOOM_MIN_PPB));
  zoomSlider.setValue(constrain(v, 0, 1));
  float ppbInit = map(zoomSlider.getValue(), 0, 1, ZOOM_MIN_PPB, ZOOM_MAX_PPB);
  wfA.setPixelsPerBeat(ppbInit);
  wfB.setPixelsPerBeat(ppbInit);

  // Pulsanti nav
  btnMain     = new Button("Main");
  btnMixer    = new Button("Mixer");
  btnSettings = new Button("Settings");

  // OSC Bridge (UNA sola istanza!)

  osc.setTargets(deckA, deckB);
  osc.setCenter(centerPanel);
  osc.setBrowser(fileBrowser);
   osc.setSettings(settings);
  centerPanel.setOsc(osc); 

  // Settings screen (schermata decoder)



  // Collega waveforms a OSC
  wfA.setOsc(osc);
  wfB.setOsc(osc);

  midi = new MidiController_Hercules(deckA, deckB, centerPanel, fileBrowser, osc);

  ac.start();
  lastMillis = millis();
}

void draw() {
  int now = millis();
  float dt = max(0, now - lastMillis) / 1000.0;
  lastMillis = now;

  background(20);
  
  deckA.updateTransport(dt);
  deckB.updateTransport(dt);

  float navH = 50;
  drawNavBar(navH);

  float contentY = navH;
  float contentH = height - navH;

  if (currentScreen == SCREEN_MAIN) {
    drawMainScreen(0, contentY, width, contentH, dt);
  } else if (currentScreen == SCREEN_MIXER) {
    drawMixerScreen(0, contentY, width, contentH);
  } else {
    drawSettingsScreen(0, contentY, width, contentH);
  }
}

void drawNavBar(float navH) {
  noStroke();
  fill(32);
  rect(0, 0, width, navH);

  float pad = 10;
  float btnW = 110;
  float btnH = navH - pad*2;

  btnMain.setBounds(pad, pad, btnW, btnH);
  btnMixer.setBounds(pad*2 + btnW, pad, btnW, btnH);
  btnSettings.setBounds(pad*3 + btnW*2, pad, btnW, btnH);

  btnMain.draw(currentScreen == SCREEN_MAIN);
  btnMixer.draw(currentScreen == SCREEN_MIXER);
  btnSettings.draw(currentScreen == SCREEN_SETTINGS);

  float zW = 240;
  float zH = 18;
  float zX = width - pad - zW;
  float zY = (navH - zH)/2f;
  zoomSlider.setBounds(zX, zY, zW, zH);
  zoomSlider.draw();

  float ppb = map(zoomSlider.getValue(), 0, 1, ZOOM_MIN_PPB, ZOOM_MAX_PPB);
  wfA.setPixelsPerBeat(ppb);
  wfB.setPixelsPerBeat(ppb);

  // Status a sinistra
  fill(220);
  textAlign(LEFT, CENTER);
  String status = osc.isConnected() ? "OSC OK" : "OSC WAIT";
  text("Screens: Main / Mixer / Settings | F: Fullscreen | " + status, pad, navH/2);

  // ==========================
  // Master tempo A (blu) e B (rosso) nello stesso box centrale
  // ==========================
  String labelA = formatMasterTime(deckA);
  String labelB = formatMasterTime(deckB);

  textSize(16); // più grande
  float tw = max(textWidth(labelA), textWidth(labelB)) + 24;
  float th = 36;

  float boxX = width/2f - tw/2f;
  float boxY = (navH - th)/2f;

  // sfondo box
  noStroke();
  fill(30, 220);
  rect(boxX, boxY, tw, th, 8);

  // righe
  float lineHy = boxY + th/2f;

  // Deck A (sopra, blu)
  textAlign(CENTER, BOTTOM);
  fill(90, 200, 255);
  text(labelA, boxX + tw/2f, lineHy - 2);

  // Deck B (sotto, rosso)
  textAlign(CENTER, TOP);
  fill(255, 110, 110);
  text(labelB, boxX + tw/2f, lineHy + 2);

  // ripristina textSize per il resto dell’interfaccia
  textSize(14);
}

void drawMainScreen(float x, float y, float w, float h, float dt) {
  float pad = 16;
  float gapWave = 6;

  // Waveforms
  float waveH = constrain(h * 0.14, 30, 72);

  float wfAX = x + pad;
  float wfAY = y + pad;
  float wfAW = w - pad*2;
  float wfAH = waveH;

  float wfBX = wfAX;
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

  float browserH = constrain(h * 0.32, 200, 380);

  float controlsY = topAfterWavesY;
  float controlsH = max(170, (y + h) - controlsY - pad - browserH - pad);

  float colGap = 16;
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

void drawSettingsScreen(float x, float y, float w, float h) {
  settings.updateLayout(x, y, w, h);
  settings.draw();
}

void drawAnalysisBadges(Deck d, float ax, float ay, float aw) {
  String msg = "";
  if (d.isAnalyzing) msg = "Analisi in corso...";
  else if (d.analysisError != null && d.analysisError.length() > 0) msg = "Analisi fallita: " + d.analysisError;
  else if (d.analysis != null) msg = "BPM: " + nf(d.analysis.bpm, 0, 1) + " • Beats: " + d.analysis.beats.size();
  else msg = "Nessuna analisi • Carica un file";

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

// Tempo master formattato per un deck
String formatMasterTime(Deck d) {
  float t = d.playheadSec;
  int totalSec = (int)t;
  int minutes  = totalSec / 60;
  int seconds  = totalSec % 60;

  float effBPM = max(1e-4, d.getEffectiveBPM());
  float period = 60.0 / effBPM; // durata beat in secondi

  float beatsFloat = t / period;       // beat index float da 0..n
  int beatIndex    = (int)floor(beatsFloat);
  int barIndex     = beatIndex / 4;    // 0..n
  int beatInBar    = (beatIndex % 4) + 1; // 1..4

  float frac = beatsFloat - beatIndex; // 0..1
  if (frac < 0) frac = 0;
  if (frac > 1) frac = 1;

  String timeStr = nf(minutes, 2) + ":" + nf(seconds, 2);
  String barStr  = str(barIndex);
  String beatStr = str(beatInBar);
  String fracStr = nf(frac, 0, 2);

  return timeStr + " | " + barStr + " : " + beatStr + " : " + fracStr;
}

// ==============================
// Fullscreen helpers
// ==============================
boolean isMac() {
  String os = System.getProperty("os.name");
  return os != null && os.toLowerCase().contains("mac");
}
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
  if (w instanceof java.awt.Frame) ((java.awt.Frame) w).setResizable(res);
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

// ==============================
// Eventi mouse / tastiera
// ==============================
void mousePressed() {
  if (btnMain.contains(mouseX, mouseY))    { currentScreen = SCREEN_MAIN; return; }
  if (btnMixer.contains(mouseX, mouseY))   { currentScreen = SCREEN_MIXER; return; }
  if (btnSettings.contains(mouseX, mouseY)){ currentScreen = SCREEN_SETTINGS; return; }
  if (zoomSlider.contains(mouseX, mouseY)) { zoomSlider.mousePressed(mouseX, mouseY); return; }

  if (currentScreen == SCREEN_MAIN) {
    wfA.mousePressed(mouseX, mouseY);
    wfB.mousePressed(mouseX, mouseY);
    deckA.mousePressed(mouseX, mouseY);
    deckB.mousePressed(mouseX, mouseY);
    centerPanel.mousePressed(mouseX, mouseY);
    fileBrowser.mousePressed(mouseX, mouseY);
  } else if (currentScreen == SCREEN_MIXER) {
    mixer.mousePressed(mouseX, mouseY);
  } else {
    settings.mousePressed(mouseX, mouseY);
  }
}

void mouseDragged() {
  if (zoomSlider.dragging) { zoomSlider.mouseDragged(mouseX, mouseY); return; }

  if (currentScreen == SCREEN_MAIN) {
    wfA.mouseDragged(mouseX, mouseY);
    wfB.mouseDragged(mouseX, mouseY);
    deckA.mouseDragged(mouseX, mouseY);
    deckB.mouseDragged(mouseX, mouseY);
    centerPanel.mouseDragged(mouseX, mouseY);
    fileBrowser.mouseDragged(mouseX, mouseY);
  } else if (currentScreen == SCREEN_MIXER) {
    mixer.mouseDragged(mouseX, mouseY);
  } else {
    settings.mouseDragged(mouseX, mouseY);
  }
}

void mouseReleased() {
  zoomSlider.mouseReleased(mouseX, mouseY);

  if (currentScreen == SCREEN_MAIN) {
    wfA.mouseReleased(mouseX, mouseY);
    wfB.mouseReleased(mouseX, mouseY);
    deckA.mouseReleased(mouseX, mouseY);
    deckB.mouseReleased(mouseX, mouseY);
    centerPanel.mouseReleased(mouseX, mouseY);
    fileBrowser.mouseReleased(mouseX, mouseY);
  } else if (currentScreen == SCREEN_MIXER) {
    mixer.mouseReleased(mouseX, mouseY);
  } else {
    settings.mouseReleased(mouseX, mouseY);
  }
}

void mouseWheel(MouseEvent event) {
  if (currentScreen == SCREEN_MAIN) fileBrowser.mouseWheel(event.getCount());
}

void keyPressed() {
  if (key == 'm' || key == 'M') {
    currentScreen = (currentScreen == SCREEN_MAIN) ? SCREEN_MIXER : SCREEN_MAIN;
  } else if (key == 's' || key == 'S') {
    currentScreen = SCREEN_SETTINGS;
  } else if (key == 'f' || key == 'F') {
    toggleFullscreen();
  }
}

void stop() {
  if (midi != null) midi.dispose();
  super.stop();
}
