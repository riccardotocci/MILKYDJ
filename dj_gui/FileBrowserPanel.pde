// FileBrowserPanel: AGGIORNATO con il metodo analyzeSelected() che usa il comando conda corretto

import java.util.Arrays;
import java.util.HashSet;
import java.util.ArrayList;
import java.util.HashMap;

class FileBrowserPanel {
  Deck deckA, deckB;

  float x, y, w, h;

  // Layout
  float headerH = 32;
  float toolbarH = 32;
  float footerH = 38;

  float leftFrac = 0.32;
  float minLeftW = 160;
  float splitterX;
  float splitterW = 6;
  boolean draggingSplitter = false;
  float dragDX = 0;

  // Liste dati
  java.io.File currentDir;
  ArrayList<java.io.File> folderList = new ArrayList<java.io.File>();
  ArrayList<java.io.File> fileList   = new ArrayList<java.io.File>();
  int selFolderIdx = -1;
  int selFileIdx   = -1;

  // Filtri
  HashSet<String> AUDIO_EXT = new HashSet<String>(Arrays.asList(
    "wav","mp3","aiff","aif","flac","ogg","opus","m4a","aac","alac","wv"
  ));

  // Stato stems e sessione
  HashMap<String, Boolean> stemsReadyByPath = new HashMap<String, Boolean>();
  HashSet<String> loadedInSession = new HashSet<String>();

  // Config stems richiesti
  String[] REQUIRED_STEMS = new String[] { "drums.wav", "vocals.wav", "other.wav", "bass.wav" };
  String extraStemName = "";

  // Scrolling
  MiniScroll foldersScroll = new MiniScroll();
  MiniScroll filesScroll   = new MiniScroll();

  // Doppio click
  long lastClickMillis = 0;
  int  lastClickFileIdx = -1;
  int  doubleClickMs = 350;

  // Pulsanti
  Button btnUp      = new Button("Up");
  Button btnAnalyze = new Button("Analyze");
  Button btnLoadA   = new Button("Load A");
  Button btnLoadB   = new Button("Load B");

  // Sensibilità scroll
  final int SCROLL_ROWS_PER_NOTCH = 1;

  // Auto refresh ogni 20s
  final int AUTO_REFRESH_MS = 20000;
  int lastRefreshMs = 0;

  // Toast piccolo messaggio
  String toastMsg = "";
  int toastUntilMs = 0;

  FileBrowserPanel(Deck A, Deck B) {
    this.deckA = A;
    this.deckB = B;

    String start = sketchPath();
    java.io.File f = (start != null) ? new java.io.File(start) : new java.io.File(System.getProperty("user.home"));
    if (!f.exists() || !f.isDirectory()) f = new java.io.File(System.getProperty("user.home"));
    openFolder(f);
  }

  void resetSessionFlags() {
    loadedInSession.clear();
  }

  void setExtraStemName(String name) {
    extraStemName = (name == null) ? "" : name.trim();
  }

  void updateLayout(float x, float y, float w, float h) {
    this.x = x; this.y = y; this.w = w; this.h = h;

    float leftW = max(minLeftW, w * leftFrac);
    leftW = min(leftW, w - 240);
    splitterX = x + leftW;

    float pad = 8;
    float bH = toolbarH - pad*2;
    float bW = 80;
    btnUp.setBounds(x + pad, y + headerH + pad, 60, bH);

    float rightButtonsX = x + w - pad - (bW*3 + 8*2);
    btnAnalyze.setBounds(rightButtonsX,              y + headerH + pad, bW, bH);
    btnLoadA.setBounds(rightButtonsX + bW + 8,      y + headerH + pad, bW, bH);
    btnLoadB.setBounds(rightButtonsX + bW*2 + 8*2,  y + headerH + pad, bW, bH);

    float listsTop = y + headerH + toolbarH;
    float listsH   = h - headerH - toolbarH - footerH;

    foldersScroll.setBounds(splitterX - 10, listsTop + 4, 6, listsH - 8);
    filesScroll.setBounds(x + w - 10,      listsTop + 4, 6, listsH - 8);
  }

  void draw() {
    if (millis() - lastRefreshMs >= AUTO_REFRESH_MS) {
      rescanAndCheckStems();
    }

    noStroke(); fill(26); rect(x, y, w, h, 8);
    fill(32); rect(x, y, w, headerH);
    fill(220); textAlign(LEFT, CENTER); textSize(14);
    text("Finder", x + 10, y + headerH/2);

    fill(28); rect(x, y + headerH, w, toolbarH);
    fill(180); textAlign(LEFT, CENTER); textSize(12);
    String path = (currentDir != null) ? currentDir.getAbsolutePath() : "";
    text(path, x + 80, y + headerH + toolbarH/2);

    btnUp.draw(false);
    btnAnalyze.draw(false);
    btnLoadA.draw(false);
    btnLoadB.draw(false);

    float listsTop = y + headerH + toolbarH;
    float listsH   = h - headerH - toolbarH - footerH;

    float foldersLeft = x;
    float foldersRight = splitterX - splitterW/2;
    float foldersW = foldersRight - foldersLeft;
    drawFolderList(foldersLeft, listsTop, foldersW, listsH);

    drawSplitter(splitterX - splitterW/2, listsTop, splitterW, listsH);

    float filesLeft = splitterX + splitterW/2;
    float filesW = x + w - filesLeft;
    drawFileList(filesLeft, listsTop, filesW, listsH);

    fill(28); rect(x, y + h - footerH, w, footerH);
    fill(200); textAlign(LEFT, CENTER); textSize(12);
    String info = (selFileIdx >= 0 && selFileIdx < fileList.size())
      ? fileList.get(selFileIdx).getName()
      : "Seleziona un file audio";
    text(info, x + 10, y + h - footerH/2);

    if (millis() < toastUntilMs && toastMsg != null && toastMsg.length() > 0) {
      String msg = toastMsg;
      float tw = textWidth(msg) + 16;
      float th = 22;
      float bx = x + w - tw - 12;
      float by = y + headerH + 6;
      noStroke();
      fill(30, 30, 30, 220);
      rect(bx, by, tw, th, 6);
      fill(230);
      textAlign(LEFT, CENTER);
      text(msg, bx + 8, by + th/2);
    }
  }

  void showToast(String msg, int ms) {
    toastMsg = msg;
    toastUntilMs = millis() + max(500, ms);
  }

  void rescanAndCheckStems() {
    rescan();
    checkAllStems();
    lastRefreshMs = millis();
  }

  void rescan() {
    folderList.clear();
    fileList.clear();

    if (currentDir == null || !currentDir.exists()) return;

    java.io.File[] all = currentDir.listFiles();
    if (all == null) all = new java.io.File[0];

    Arrays.sort(all, (a, b) -> a.getName().compareToIgnoreCase(b.getName()));

    for (java.io.File f : all) {
      if (f.isDirectory() && !f.isHidden()) {
        folderList.add(f);
      } else if (f.isFile() && isAudio(f) && !f.isHidden()) {
        fileList.add(f);
      }
    }

    selFolderIdx = -1;
    selFileIdx = min(selFileIdx, fileList.size() - 1);

    foldersScroll.setContent(folderList.size());
    filesScroll.setContent(fileList.size());
  }

  void checkAllStems() {
    stemsReadyByPath.clear();
    for (java.io.File f : fileList) {
      boolean ok = checkStemsForFile(f);
      stemsReadyByPath.put(f.getAbsolutePath(), ok);
    }
  }

  boolean checkStemsForFile(java.io.File audioFile) {
    try {
      java.io.File parent = audioFile.getParentFile();
      String base = baseName(audioFile.getName());
      java.io.File stemsDir = new java.io.File(new java.io.File(parent, "stems"), base);

      if (!stemsDir.exists() || !stemsDir.isDirectory()) return false;

      for (String stem : REQUIRED_STEMS) {
        java.io.File s = new java.io.File(stemsDir, stem);
        if (!s.exists() || !s.isFile()) return false;
      }
      if (extraStemName != null && extraStemName.length() > 0) {
        java.io.File extra = new java.io.File(stemsDir, extraStemName);
        if (!extra.exists() || !extra.isFile()) return false;
      }
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  String baseName(String fileName) {
    int dot = fileName.lastIndexOf('.');
    return (dot < 0) ? fileName : fileName.substring(0, dot);
  }

  boolean isAudio(java.io.File f) {
    String n = f.getName();
    int dot = n.lastIndexOf('.');
    if (dot < 0) return false;
    String ext = n.substring(dot + 1).toLowerCase();
    return AUDIO_EXT.contains(ext);
  }

  void drawFolderList(float bx, float by, float bw, float bh) {
    noStroke(); fill(24); rect(bx, by, bw, bh);

    int rowH = 26;
    int visible = max(1, floor((bh - 8) / rowH));
    foldersScroll.setViewport(visible);
    int offset = foldersScroll.getOffset();

    fill(140); textAlign(LEFT, CENTER); textSize(12);
    text("Folders", bx + 8, by + 12);

    float listY = by + 18;
    for (int i = 0; i < visible; i++) {
      int idx = offset + i;
      if (idx >= folderList.size()) break;

      float ry = listY + i * rowH;
      boolean selected = (idx == selFolderIdx);
      boolean hover = mouseX >= bx && mouseX <= bx + bw && mouseY >= ry && mouseY <= ry + rowH;

      if (selected) { fill(50, 140); rect(bx + 2, ry, bw - 4 - 8, rowH, 6); }
      else if (hover) { fill(40, 120); rect(bx + 2, ry, bw - 4 - 8, rowH, 6); }

      fill(210); textAlign(LEFT, CENTER); textSize(12);
      text(folderList.get(idx).getName(), bx + 10, ry + rowH/2);
    }
    foldersScroll.draw();
  }

  void drawFileList(float bx, float by, float bw, float bh) {
    noStroke(); fill(24); rect(bx, by, bw, bh);

    int rowH = 26;
    int visible = max(1, floor((bh - 8) / rowH));
    filesScroll.setViewport(visible);
    int offset = filesScroll.getOffset();

    fill(140); textAlign(LEFT, CENTER); textSize(12);
    text("Audio files", bx + 8, by + 12);

    float listY = by + 18;
    for (int i = 0; i < visible; i++) {
      int idx = offset + i;
      if (idx >= fileList.size()) break;

      java.io.File f = fileList.get(idx);
      String key = f.getAbsolutePath();
      Boolean rr = stemsReadyByPath.get(key);
      boolean ready = (rr != null && rr.booleanValue());
      boolean loaded = loadedInSession.contains(key);

      float ry = listY + i * rowH;
      float rx = bx + 2;
      float rw = bw - 4 - 8;

      if (loaded) {
        fill(90, 90, 90, 160);
        rect(rx, ry, rw, rowH, 6);
      } else if (ready) {
        fill(40, 120, 70, 140);
        rect(rx, ry, rw, rowH, 6);
      }

      boolean selected = (idx == selFileIdx);
      boolean hover = mouseX >= bx && mouseX <= bx + bw && mouseY >= ry && mouseY <= ry + rowH;

      if (selected) { fill(50, 140); rect(rx, ry, rw, rowH, 6); }
      else if (hover) { fill(40, 120); rect(rx, ry, rw, rowH, 6); }

      int txtCol = loaded ? color(190) : (ready ? color(230) : color(210));
      fill(txtCol);
      textAlign(LEFT, CENTER); textSize(12);
      text(f.getName(), bx + 10, ry + rowH/2);
    }
    filesScroll.draw();
  }

  void drawSplitter(float sx, float sy, float sw, float sh) {
    noStroke();
    fill(36); rect(sx, sy, sw, sh);
    fill(60); rect(sx + sw/2f - 1, sy + sh*0.45f, 2, sh*0.10f, 2);
  }

  void mousePressed(float mx, float my) {
    float listsTop = y + headerH + toolbarH;
    float listsH   = h - headerH - toolbarH - footerH;
    if (mx >= splitterX - splitterW/2 && mx <= splitterX + splitterW/2 && my >= listsTop && my <= listsTop + listsH) {
      draggingSplitter = true;
      dragDX = mx - splitterX;
      return;
    }

    if (mx >= foldersScroll.x && mx <= foldersScroll.x + foldersScroll.w && my >= foldersScroll.y && my <= foldersScroll.y + foldersScroll.h) {
      foldersScroll.mousePressed(mx, my);
      return;
    }
    if (mx >= filesScroll.x && mx <= filesScroll.x + filesScroll.w && my >= filesScroll.y && my <= filesScroll.y + filesScroll.h) {
      filesScroll.mousePressed(mx, my);
      return;
    }

    btnUp.mousePressed(mx, my);
    btnAnalyze.mousePressed(mx, my);
    btnLoadA.mousePressed(mx, my);
    btnLoadB.mousePressed(mx, my);

    float foldersLeft = x;
    float foldersRight = splitterX - splitterW/2;
    float foldersW = foldersRight - foldersLeft;
    if (mx >= foldersLeft && mx <= foldersRight) {
      clickFolderList(mx, my, foldersLeft, y + headerH + toolbarH, foldersW, h - headerH - toolbarH - footerH);
    }

    float filesLeft = splitterX + splitterW/2;
    float filesW = x + w - filesLeft;
    if (mx >= filesLeft && mx <= x + w) {
      clickFileList(mx, my, filesLeft, y + headerH + toolbarH, filesW, h - headerH - toolbarH - footerH);
    }
  }

  void mouseDragged(float mx, float my) {
    if (draggingSplitter) {
      float newSplitX = mx - dragDX;
      float leftW = constrain(newSplitX - x, minLeftW, w - 240);
      leftFrac = leftW / w;
      splitterX = x + leftW;
      return;
    }
    foldersScroll.mouseDragged(mx, my);
    filesScroll.mouseDragged(mx, my);
  }

  void mouseReleased(float mx, float my) {
    if (btnUp.pressed && btnUp.contains(mx, my)) navigateUp();
    btnUp.mouseReleased(mx, my);

    if (btnAnalyze.pressed && btnAnalyze.contains(mx, my)) analyzeSelected();
    btnAnalyze.mouseReleased(mx, my);

    if (btnLoadA.pressed && btnLoadA.contains(mx, my)) loadSelectedToDeck(deckA);
    btnLoadA.mouseReleased(mx, my);

    if (btnLoadB.pressed && btnLoadB.contains(mx, my)) loadSelectedToDeck(deckB);
    btnLoadB.mouseReleased(mx, my);

    draggingSplitter = false;
    foldersScroll.mouseReleased(mx, my);
    filesScroll.mouseReleased(mx, my);
  }

  void mouseWheel(int count) {
    float listsTop = y + headerH + toolbarH;
    float listsH   = h - headerH - toolbarH - footerH;
    if (mouseY < listsTop || mouseY > listsTop + listsH) return;

    if (count == 0) return;
    int dir = (count > 0) ? +1 : -1;
    int stepRows = dir * SCROLL_ROWS_PER_NOTCH;

    float foldersLeft  = x;
    float foldersRight = splitterX - splitterW/2;
    float filesLeft    = splitterX + splitterW/2;

    if (mouseX >= foldersLeft && mouseX <= foldersRight) {
      foldersScroll.stepItems(stepRows);
    } else if (mouseX >= filesLeft && mouseX <= x + w) {
      filesScroll.stepItems(stepRows);
    }
  }

  void openFolder(java.io.File dir) {
    currentDir = dir;
    rescanAndCheckStems();
  }

  void navigateUp() {
    if (currentDir == null) return;
    java.io.File parent = currentDir.getParentFile();
    if (parent != null && parent.exists()) {
      openFolder(parent);
    }
  }

  void clickFolderList(float mx, float my, float bx, float by, float bw, float bh) {
    int rowH = 26;
    int visible = max(1, floor((bh - 8) / rowH));
    foldersScroll.setViewport(visible);
    int offset = foldersScroll.getOffset();

    float listY = by + 18;
    if (my < listY) return;
    int idx = floor((my - listY) / rowH) + offset;
    if (idx >= 0 && idx < folderList.size()) {
      selFolderIdx = idx;
      openFolder(folderList.get(idx));
    }
  }

  void clickFileList(float mx, float my, float bx, float by, float bw, float bh) {
    int rowH = 26;
    int visible = max(1, floor((bh - 8) / rowH));
    filesScroll.setViewport(visible);
    int offset = filesScroll.getOffset();

    float listY = by + 18;
    if (my < listY) return;

    int idx = floor((my - listY) / rowH) + offset;
    if (idx >= 0 && idx < fileList.size()) {
      long now = millis();
      if (idx == lastClickFileIdx && (now - lastClickMillis) <= doubleClickMs) {
        java.io.File f = fileList.get(idx);
        if (isReady(f)) {
          loadSelectedToDeck(deckA, f);
        } else {
          showToast("Analyze first", 1500);
        }
        lastClickFileIdx = -1;
      } else {
        selFileIdx = idx;
        lastClickFileIdx = idx;
        lastClickMillis = now;
      }
    }
  }

  boolean isReady(java.io.File f) {
    Boolean b = stemsReadyByPath.get(f.getAbsolutePath());
    return b != null && b.booleanValue();
  }

  void noteLoaded(java.io.File f) {
    if (f != null) loadedInSession.add(f.getAbsolutePath());
  }

  void loadSelectedToDeck(Deck deck) {
    if (selFileIdx < 0 || selFileIdx >= fileList.size()) return;
    java.io.File f = fileList.get(selFileIdx);
    if (!isReady(f)) { showToast("Analyze first", 1500); return; }
    loadSelectedToDeck(deck, f);
  }

  void loadSelectedToDeck(Deck deck, java.io.File f) {
    try {
      deck.loadAudioFile(f);
      noteLoaded(f);
    } catch (Exception ex) {
      println("Errore caricamento file: " + ex);
    }
  }

// --- ANALYZE con il comando Python diretto, workDir e log completo ---
void analyzeSelected() {
  if (selFileIdx < 0 || selFileIdx >= fileList.size()) {
    println("[Analyze] Nessun file selezionato.");
    return;
  }
  
  java.io.File f = fileList.get(selFileIdx);
  String songPath = f.getAbsolutePath();
  String fileName = f.getName();
  
  String pythonPath = "/opt/anaconda3/envs/dj_ambisonics/bin/python";
  String scriptPath = "/Users/riccardotocci/Desktop/cpac_work/dj_ambisonics/ambisonics_automation.py";
  String workDir = "/Users/riccardotocci/Desktop/cpac_work/dj_ambisonics";
  
  println("🎵 Processing: " + fileName);
  
  try {
    // Comando completo con cd nella working directory
    String command = "cd " + workDir + " && " + pythonPath + " " + scriptPath + " \"" + songPath + "\"";
    String[] cmd = {"/bin/bash", "-c", command};
    
    ProcessBuilder pb = new ProcessBuilder(cmd);
    pb.redirectErrorStream(true); // Unisce stdout e stderr
    
    final Process process = pb.start();
    
    // Thread per leggere l'output del processo in tempo reale
    new Thread(() -> {
      try {
        java.io.BufferedReader reader = new java.io.BufferedReader(
          new java.io.InputStreamReader(process.getInputStream())
        );
        String line;
        while ((line = reader.readLine()) != null) {
          println("[Python] " + line);
        }
        reader.close();
        
        int exitCode = process.waitFor();
        println("[Analyze] Processo terminato con codice: " + exitCode);
        
      } catch (Exception ex) {
        println("[Analyze] Errore lettura output: " + ex);
        ex.printStackTrace();
      }
    }).start();
    
    showToast("Analysis started...", 2000);
    
  } catch (Exception ex) {
    println("[Analyze] Errore avvio comando: " + ex);
    ex.printStackTrace();
    showToast("Error starting analysis", 2000);
  }
}
}


// --- MiniScroll (invariato) ---
class MiniScroll {
  float x, y, w, h;
  int totalItems = 0, visibleItems = 0;
  float pos = 0;
  boolean dragging = false;
  float dragDY = 0;

  void setBounds(float x, float y, float w, float h) { this.x=x; this.y=y; this.w=w; this.h=h; }
  void setContent(int t) { totalItems = max(0, t); pos = constrain(pos, 0, 1); }
  void setViewport(int v) { visibleItems = max(1, v); }
  int getOffset() {
    if (totalItems <= visibleItems) return 0;
    return round(pos * (totalItems - visibleItems));
  }
  void stepItems(int delta) {
    if (visibleItems <= 0 || totalItems <= visibleItems) { pos = 0; return; }
    int maxOff = totalItems - visibleItems;
    int newOff = constrain(getOffset() + delta, 0, maxOff);
    pos = (maxOff == 0) ? 0 : (newOff / (float)maxOff);
  }
  void draw() {
    if (totalItems <= 0) return;
    noStroke(); fill(36); rect(x, y, w, h, 3);
    float frac = (totalItems <= 0) ? 1 : min(1, (float)visibleItems / max(1, totalItems));
    float knobH = max(20, h * frac);
    float track = h - knobH;
    float knobY = y + track * pos;
    fill(90); rect(x, knobY, w, knobH, 3);
  }
  void mouseDragged(float mx, float my) {
    if (!dragging) return;
    float frac = (totalItems <= 0) ? 1 : min(1, (float)visibleItems / max(1, totalItems));
    float knobH = max(20, h * frac);
    float track = h - knobH;
    float ny = constrain(my - y - dragDY, 0, track);
    pos = (track <= 0) ? 0 : (ny / track);
  }
  void mouseReleased(float mx, float my) { dragging = false; }
  void mousePressed(float mx, float my) {
    float frac = (totalItems <= 0) ? 1 : min(1, (float)visibleItems / max(1, totalItems));
    float knobH = max(20, h * frac);
    float track = h - knobH;
    float knobY = y + track * pos;
    if (mx >= x && mx <= x + w && my >= knobY && my <= knobY + knobH) {
      dragging = true;
      dragDY = my - knobY;
    }
  }
}
