/**
 * OscBridge.pde (AGGIORNATO per gestione encoders)
 *
 * Bridge OSC Processing ⇄ SuperCollider per MILKY_DJ.
 * (Mantiene tutte le funzioni esistenti + aggiunge supporto ai canali encoder per la schermata mixer)
 *
 * Nuovi indirizzi gestiti:
 *   /dj3d/deck/encoders      (count canali per deck)
 *   /dj3d/deck/encoder       (nome singolo canale)
 *   /dj3d/deck/encoder_level (livello tempo reale, da /tr)
 *   /dj3d/deck/encoder/editor (richiesta apertura/chiusura editor encoder singolo)
 */

import oscP5.*;
import netP5.*;
import java.io.File;
import java.util.ArrayList;

class OscBridge {

  // ============================
  // Config rete
  // ============================
  int localPort = 57121;
  String scHost = "127.0.0.1";
  int scPort    = 57120;

  // ============================
  // Core OSC
  // ============================
  private final PApplet app;
  private OscP5 osc;
  private NetAddress sc;

  // ============================
  // Riferimenti UI
  // ============================
  Deck deckA;
  Deck deckB;
  MixerCenterPanel center;
  FileBrowserPanel browser;
  SettingsScreen settings;

  // ============================
  // Stato interno
  // ============================
  boolean debug = true;
  boolean connected = false;
  boolean receivedHello = false;

  // === NUOVO: dati encoder per ogni deck ===
  ArrayList<EncoderChannelInfo> encA = new ArrayList<EncoderChannelInfo>();
  ArrayList<EncoderChannelInfo> encB = new ArrayList<EncoderChannelInfo>();

  // ============================
  // Costruttore
  // ============================
  OscBridge(PApplet app) {
    if (app == null) throw new IllegalArgumentException("PApplet nullo");
    this.app = app;
    initOsc();
  }

  // ============================
  // Init OSC
  // ============================
  private void initOsc() {
    try {
      osc = new OscP5(app, localPort);
      sc  = new NetAddress(scHost, scPort);
      plugIncomings();
      log("Bridge online (listen " + localPort + " → send " + scHost + ":" + scPort + ")");
    } catch (Exception e) {
      app.println("[OscBridge][ERR] initOsc: " + e);
      e.printStackTrace();
    }
  }

  // ============================
  // Setter riferimenti
  // ============================
  void setTargets(Deck a, Deck b) { deckA = a; deckB = b; }
  void setCenter(MixerCenterPanel c) { center = c; }
  void setBrowser(FileBrowserPanel b) { browser = b; }
  void setSettings(SettingsScreen s) { settings = s; }

  // ============================
  // Logging
  // ============================
  private void log(String s) { if (debug) app.println("[OSC] " + s); }

  // ============================
  // Helpers ID deck
  // ============================
  private char idOf(Deck d) {
    if (d == null) return '?';
    if (d == deckA) return 'A';
    if (d == deckB) return 'B';
    return '?';
  }
  private Deck deckById(String id) {
    if (id == null || id.isEmpty()) return null;
    char c = Character.toUpperCase(id.charAt(0));
    if (c == 'A') return deckA;
    if (c == 'B') return deckB;
    return null;
  }
  private ArrayList<EncoderChannelInfo> listForDeckId(String deckId) {
    if (deckId == null) return encA; // default
    return deckId.equalsIgnoreCase("A") ? encA : encB;
  }
  private void ensureEncoderListSize(ArrayList<EncoderChannelInfo> list, int size) {
    while (list.size() < size) {
      EncoderChannelInfo ci = new EncoderChannelInfo();
      ci.name = "Ch " + list.size();
      ci.level = 0;
      ci.editorOpen = false;
      list.add(ci);
    }
  }
  private void initEncodersForDeck(String deckId, int count) {
    ArrayList<EncoderChannelInfo> list = listForDeckId(deckId);
    list.clear();
    ensureEncoderListSize(list, Math.max(0, count));
  }

  // ============================
  // Invio messaggi OSC
  // ============================
  private void send(String addr, Object... args) {
    if (osc == null || sc == null) {
      if (debug) app.println("[OSC][WARN] invio ignorato (osc/sc null): " + addr);
      return;
    }
    OscMessage m = new OscMessage(addr);
    for (Object a : args) {
      if (a == null) continue;
      if (a instanceof String)         m.add((String)a);
      else if (a instanceof Character) m.add(String.valueOf((char)a));
      else if (a instanceof Integer)   m.add((int)a);
      else if (a instanceof Float)     m.add((float)a);
      else if (a instanceof Double)    m.add(((Double)a).floatValue());
      else if (a instanceof Boolean)   m.add(((Boolean)a) ? 1 : 0);
      else m.add(a.toString());
    }
    osc.send(m, sc);
    if (debug) app.println("[OSC][OUT] " + addr + " " + java.util.Arrays.toString(args));
  }

  // ============================
  // Metodi INVIO (public)
  // ============================
  void deckLoadFile(Deck d, File f) {
    char id = idOf(d); if (id == '?' || f == null) return;
    send("/dj3d/deck/load_file", String.valueOf(id), f.getAbsolutePath());
  }
  void sendLoadToDeck(Deck d, File f) { deckLoadFile(d, f); }
  void deckSetVolume(Deck d, float vol01) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/volume", String.valueOf(id), constrain(vol01, 0, 1));
  }
  void deckSetSpeed(Deck d, float factor) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/speed", String.valueOf(id), factor);
  }
  void crossfader(float x01) { send("/dj3d/crossfader", constrain(x01, 0, 1)); }
  void deckSetCue(Deck d, float seconds) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/set_cue", String.valueOf(id), seconds);
  }
  void deckSeek(Deck d, float seconds) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/seek", String.valueOf(id), seconds);
  }
  void deckCueHold(Deck d, boolean on) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/cue_hold", String.valueOf(id), on);
  }
  void deckPlay(Deck d) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/play", String.valueOf(id));
  }
  void deckPlayAt(Deck d, float seconds) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/play", String.valueOf(id), seconds);
  }
  void deckStop(Deck d) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/stop", String.valueOf(id));
  }
  void deckSetBPM(Deck d, float bpmTarget) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/bpm", String.valueOf(id), bpmTarget);
  }
  void deckSetLoopIn(Deck d, float sec) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/loop_in", String.valueOf(id), sec);
  }
  void deckSetLoopOut(Deck d, float sec) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/loop_out", String.valueOf(id), sec);
  }
  void deckSetLoopEnable(Deck d, boolean on) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/loop_enable", String.valueOf(id), on);
  }
  void deckCueVolume(Deck d, float vol01) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/cue_volume", String.valueOf(id), constrain(vol01, 0, 1));
  }
  void phonesOut(int outIdx) { send("/dj3d/phones/out", outIdx); }
  void loadAnalysis(String path) { send("/dj3d/load_analysis", path); }
  void randomAz()   { send("/dj3d/random_az"); }
  void shuffleLfo() { send("/dj3d/shuffle_lfo"); }
  void addReverb()  { send("/dj3d/add_reverb"); }
  void switchDecoder(String t) { send("/dj3d/switch_decoder", t); }
  void decoderEditor(boolean on) { send("/dj3d/decoder/editor", on); }
  void record(boolean on, String pathOrNull) {
    if (pathOrNull == null || pathOrNull.isEmpty()) send("/dj3d/record", on);
    else send("/dj3d/record", on, pathOrNull);
  }
  void freeAll() { send("/dj3d/free_all"); }

  // === NUOVO: apertura editor encoder singolo ===
  void deckEncoderEditor(Deck deck, int idx, boolean on) {
    char id = idOf(deck);
    if (id == '?') return;
    send("/dj3d/deck/encoder/editor", String.valueOf(id), idx, on);
  }

  // ============================
  // Registrazione callback
  // ============================
  private void plugIncomings() {
    try {
      // Stato generale
      osc.plug(this, "onHello",        "/dj3d/hello");
      osc.plug(this, "onDecoder",      "/dj3d/decoder");
      osc.plug(this, "onReverb",       "/dj3d/reverb");
      osc.plug(this, "onPhonesOut",    "/dj3d/phones_out");
      osc.plug(this, "onGlobalBPM",    "/dj3d/global_bpm");
      osc.plug(this, "onRun",          "/dj3d/run");
      osc.plug(this, "onRecord",       "/dj3d/record");
      osc.plug(this, "onFreed",        "/dj3d/freed");
      osc.plug(this, "onWarn",         "/dj3d/warn");
      osc.plug(this, "onError",        "/dj3d/error");

      // Caricamenti / analisi
      osc.plug(this, "onStemsLoaded",   "/dj3d/stems_loaded");
      osc.plug(this, "onTrackLoaded",   "/dj3d/track_loaded");
      osc.plug(this, "onAnalysisLoaded","/dj3d/analysis_loaded");
      osc.plug(this, "onFileFinalized", "/dj3d/file_finalized");
      osc.plug(this, "onPlayEnabled",   "/dj3d/play_enabled");

      // Deck stato / cue / loop / bpm / rate / seek
      osc.plug(this, "onDeckState",     "/dj3d/deck/state");
      osc.plug(this, "onDeckCueLoaded", "/dj3d/deck/cue_loaded");
      osc.plug(this, "onDeckCueState",  "/dj3d/deck/cue_state");
      osc.plug(this, "onDeckCueVolume", "/dj3d/deck/cue_volume");
      osc.plug(this, "onDeckCuePos",    "/dj3d/deck/cue_pos");
      osc.plug(this, "onDeckLoopIn",    "/dj3d/deck/loop_in");
      osc.plug(this, "onDeckLoopOut",   "/dj3d/deck/loop_out");
      osc.plug(this, "onDeckLoopEnable","/dj3d/deck/loop_enable");
      osc.plug(this, "onDeckBPM",       "/dj3d/deck/bpm");
      osc.plug(this, "onDeckRate",      "/dj3d/deck/rate");
      osc.plug(this, "onSeekAck",       "/dj3d/deck/seek_ack");

      // Mix
      osc.plug(this, "onCrossfader",    "/dj3d/crossfader");
      osc.plug(this, "onDeckVolumeFB",  "/dj3d/deck/volume");

      // === NUOVO: encoders ===
      osc.plug(this, "onDeckEncodersCount", "/dj3d/deck/encoders");
      osc.plug(this, "onDeckEncoderInfo",   "/dj3d/deck/encoder");
      osc.plug(this, "onDeckEncoderLevel",  "/dj3d/deck/encoder_level");
    } catch (Exception e) {
      app.println("[OscBridge][ERR] plugIncomings: " + e);
      e.printStackTrace();
    }
  }

  // ============================
  // Callback RICEZIONE
  // ============================
  public void onHello(int langPort, int order, int numCh) {
    receivedHello = true;
    connected = true;
    log("SC hello: port=" + langPort + " order=" + order + " ch=" + numCh);
  }
  public void onDecoder(String type) {
    log("decoder: " + type);
    if (settings != null) settings.setActiveDecoder(type);
  }
  public void onReverb(int on) { log("reverb: " + on); }
  public void onPhonesOut(int outIdx) { log("phones out: " + outIdx); }
  public void onGlobalBPM(float bpm) { log("global BPM: " + bpm); }
  public void onRun(int on) { log("run: " + on); }
  public void onRecord(int on, String path) { log("record: " + on + " path=" + path); }
  public void onFreed() { log("freed all"); clearEncoders(); }
  public void onWarn(Object a) { log("WARN: " + a); }
  public void onError(Object a) { log("ERR: " + a); }

  public void onStemsLoaded(String deckId, String stemsDir, int count) {
    log("stems loaded deck=" + deckId + " count=" + count + " dir=" + stemsDir);
    // Pre-inizializza i canali per robustezza (anche se /dj3d/deck/encoders non arriverà)
    initEncodersForDeck(deckId, Math.max(0, count));
  }
  public void onTrackLoaded(int idx, String filename, int numCh, int isPerc, String deckId) {
    log("track loaded #" + idx + " " + filename + " ch=" + numCh + " perc=" + isPerc + " deck=" + deckId);
  }
  public void onAnalysisLoaded(String path, int matched, int total) {
    log("analysis loaded matched=" + matched + "/" + total + " path=" + path);
  }
  public void onFileFinalized(String base, int nOnsets, float bpm) {
    log("file finalized " + base + " onsets=" + nOnsets + " bpm=" + bpm);
  }
  public void onPlayEnabled(int enabled, int finalizedCount, int expected) {
    log("play enabled=" + enabled + " finalized=" + finalizedCount + "/" + expected);
  }

  public void onDeckState(String deckId, int state) {
    Deck d = deckById(deckId);
    if (d != null && d.playBtn != null) d.playBtn.setPlaying(state != 0);
    log("deck/state " + deckId + " -> " + state);
  }
  public void onDeckCueLoaded(String deckId, String path) { log("cue loaded " + deckId + " path=" + path); }
  public void onDeckCueState(String deckId, int state) { log("cue state " + deckId + " -> " + state); }
  public void onDeckCueVolume(String deckId, float v) { log("cue volume " + deckId + " -> " + v); }
  public void onDeckCuePos(String deckId, float sec) { log("cue pos " + deckId + " -> " + nf(sec,0,3)); }
  public void onDeckLoopIn(String deckId, float sec) { log("loop in " + deckId + " -> " + sec); }
  public void onDeckLoopOut(String deckId, float sec) { log("loop out " + deckId + " -> " + sec); }
  public void onDeckLoopEnable(String deckId, int on) { log("loop enable " + deckId + " -> " + on); }
  public void onDeckBPM(String deckId, float target, float ref, float rate) {
    log("deck bpm " + deckId + " target=" + target + " ref=" + ref + " rate=" + rate);
  }
  public void onDeckRate(String deckId, float rate) { log("deck rate feedback " + deckId + " -> " + rate); }
  public void onSeekAck(String deckId, float sec) { log("seek ack " + deckId + " -> " + nf(sec,0,3)); }

  public void onCrossfader(float x, float gA, float gB) {
    log("crossfader x=" + nf(x,0,3) + " gA=" + nf(gA,0,3) + " gB=" + nf(gB,0,3));
    if (center != null) center.setCrossfader(x);
  }
  public void onDeckVolumeFB(String deckId, float v) {
    log("deck volume FB " + deckId + " -> " + v);
  }

  // === NUOVE CALLBACK ENCODER ===

  // /dj3d/deck/encoders <deck> <count>
  public void onDeckEncodersCount(String deckId, int count) {
    log("encoders count deck=" + deckId + " -> " + count);
    initEncodersForDeck(deckId, Math.max(0, count));
  }

  // /dj3d/deck/encoder <deck> <idx> <name>
  public void onDeckEncoderInfo(String deckId, int idx, String name) {
    ArrayList<EncoderChannelInfo> list = listForDeckId(deckId);
    // Rende robusto: crea slot fino a idx incluso
    ensureEncoderListSize(list, idx + 1);
    list.get(idx).name = name;

    if (app.frameCount % 60 == 0) { // log ogni ~1 sec
      log("encoder info deck=" + deckId + " idx=" + idx + " name=" + name);
    }
  }

  // /dj3d/deck/encoder_level <deck> <idx> <amp>
  public void onDeckEncoderLevel(String deckId, int idx, float amp) {
    ArrayList<EncoderChannelInfo> list = listForDeckId(deckId);
    // Anche qui: crea slot se servono
    ensureEncoderListSize(list, idx + 1);
    list.get(idx).level = amp;
  }

  // Utility per liberare
  void clearEncoders() {
    encA.clear();
    encB.clear();
  }

  // Getter usato dai pannelli Mixer
  EncoderChannelInfo[] getChannelsForDeck(String deckId) {
    if (deckId == null) return null;
    if (deckId.equalsIgnoreCase("A")) return encA.toArray(new EncoderChannelInfo[0]);
    if (deckId.equalsIgnoreCase("B")) return encB.toArray(new EncoderChannelInfo[0]);
    return null;
  }
  
void requestAnalyzeFolder(String stemsPath) {
    if (!connected) {
        app.println("[OSC][WARN] SC non connesso, skip analisi");
        return;
    }
    
    // Invia direttamente al server Python (porta 57121)
    NetAddress pythonAddr = new NetAddress("127.0.0.1", 57123);
    OscMessage msg = new OscMessage("/analyze_folder");
    msg.add(stemsPath);
    
    try {
        osc.send(msg, pythonAddr);
        log("Richiesto analisi: " + stemsPath);
    } catch (Exception e) {
        app.println("[OSC][ERR] Invio /analyze_folder fallito: " + e);
    }
}

// Richiedi analisi di un singolo file
void requestAnalyzeFile(String filePath) {
    NetAddress pythonAddr = new NetAddress("127.0.0.1", 57122);
    OscMessage msg = new OscMessage("/analyze_file");
    msg.add(filePath);
    
    try {
        osc.send(msg, pythonAddr);
        log("Richiesto analisi file: " + filePath);
    } catch (Exception e) {
        app.println("[OSC][ERR] Invio /analyze_file fallito: " + e);
    }
}

  // ============================
  // Stato connessione
  // ============================
  boolean isConnected() { return connected && receivedHello; }
  void setDebug(boolean d) { debug = d; }
}

// Struttura info canale (UI bounds inclusi per hit-test)
class EncoderChannelInfo {
  String name = "";
  float level = 0;
  boolean editorOpen = false;
  // bounds pulsante editor
  float btnX, btnY, btnW, btnH;
}
