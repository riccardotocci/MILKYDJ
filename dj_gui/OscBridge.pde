/**
 * OscBridge.pde
 *
 * Bridge OSC Processing ⇄ SuperCollider per il progetto MILKY_DJ.
 *
 * FUNZIONI PRINCIPALI (INVIO verso SC):
 *   /dj3d/deck/load_file   A|B  path
 *   /dj3d/deck/volume      A|B  float(0..1)
 *   /dj3d/deck/speed       A|B  float(rate: 1.0 = normale)
 *   /dj3d/crossfader       float(0..1)
 *   /dj3d/deck/set_cue     A|B  float(seconds)   (arma il cue, non suona)
 *   /dj3d/deck/seek        A|B  float(seconds)   (sposta playhead; se playing riparte da lì)
 *   /dj3d/deck/cue_hold    A|B  int(1 press / 0 release)
 *   /dj3d/deck/play        A|B
 *   /dj3d/deck/stop        A|B
 *   /dj3d/deck/bpm         A|B  float(target BPM)
 *   /dj3d/deck/loop_in     A|B  float(seconds)
 *   /dj3d/deck/loop_out    A|B  float(seconds)
 *   /dj3d/deck/loop_enable A|B  int(0/1)
 *   /dj3d/deck/cue_volume  A|B  float(0..1) (volume file singolo in cuffia)
 *   /dj3d/phones/out       int(outIndex)
 *   /dj3d/random_az
 *   /dj3d/shuffle_lfo
 *   /dj3d/add_reverb
 *   /dj3d/switch_decoder   "simple" | "binaural"
 *   /dj3d/record           int(0/1) [path opzionale]
 *   /dj3d/load_analysis    pathJson
 *   /dj3d/free_all
 *
 * CALLBACK (RICEZIONE da SC → aggiorna UI dove possibile):
 *   /dj3d/hello, /dj3d/decoder, /dj3d/run, /dj3d/deck/state, /dj3d/crossfader, /dj3d/deck/cue_pos ...
 *
 * NOTE:
 * - Tutti i metodi di invio usano tipi primitivi (float/int/String).
 * - I boolean vengono sempre inviati come int 0/1 (SC li interpreta con asInteger/asBoolean).
 * - Compat: metodo sendLoadToDeck(Deck, File) mantiene vecchio nome usato nel codice precedente.
 */

import oscP5.*;
import netP5.*;
import java.io.File;

class OscBridge {

  // ============================
  // CONFIG RETE
  // ============================
  int localPort = 57121;        // Porta su cui Processing ascolta (SC invia verso questa)
  String scHost = "127.0.0.1";  // Host SuperCollider
  int scPort = 57120;           // Porta SuperCollider (predefinita)

  // ============================
  // CORE OSC
  // ============================
  private final PApplet app;
  private OscP5 osc;
  private NetAddress sc;

  // ============================
  // RIFERIMENTI UI (usa setter)
  // ============================
  private Deck deckA;
  private Deck deckB;
  private MixerCenterPanel center;
  private FileBrowserPanel browser;

  // ============================
  // STATO / FLAG
  // ============================
  boolean debug = true;
  boolean connected = false;
  boolean receivedHello = false;

  // ============================
  // COSTRUTTORE
  // ============================
  OscBridge(PApplet app) {
    if (app == null) throw new IllegalArgumentException("PApplet nullo");
    this.app = app;
    initOsc();
  }

  // ============================
  // INIZIALIZZAZIONE OSC
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
  // SETTER RIFERIMENTI
  // ============================
  void setTargets(Deck a, Deck b) { deckA = a; deckB = b; }
  void setCenter(MixerCenterPanel c) { center = c; }
  void setBrowser(FileBrowserPanel b) { browser = b; }

  // ============================
  // LOG / DEBUG
  // ============================
  private void log(String s) { if (debug) app.println("[OSC] " + s); }

  // ============================
  // HELPERS
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

  private void send(String addr, Object... args) {
    if (osc == null || sc == null) {
      if (debug) app.println("[OSC][WARN] invio ignorato (osc/sc null): " + addr);
      return;
    }
    OscMessage m = new OscMessage(addr);
    for (Object a : args) {
      if (a == null) continue;
      if (a instanceof String)      m.add((String)a);
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

  // =========================================================
  // INVIO COMANDI (Processing → SuperCollider)
  // =========================================================

  // Carica file principale (CUE + stems + JSON)
  void deckLoadFile(Deck d, File f) {
    char id = idOf(d); if (id == '?' || f == null) return;
    send("/dj3d/deck/load_file", String.valueOf(id), f.getAbsolutePath());
  }
  // Compat vecchio nome
  void sendLoadToDeck(Deck d, File f) { deckLoadFile(d, f); }

  // Volume deck (0..1)
  void deckSetVolume(Deck d, float vol01) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/volume", String.valueOf(id), constrain(vol01, 0, 1));
  }

  // Speed (rate playback) come numero (1.0 = normale)
  void deckSetSpeed(Deck d, float factor) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/speed", String.valueOf(id), factor);
  }

  // Crossfader
  void crossfader(float x01) { send("/dj3d/crossfader", constrain(x01, 0, 1)); }

  // Imposta CUE (arma posizione senza suonare)
  void deckSetCue(Deck d, float seconds) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/set_cue", String.valueOf(id), seconds);
  }

  // Seek attivo (sposta playhead; se playing riparte da lì)
  void deckSeek(Deck d, float seconds) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/seek", String.valueOf(id), seconds);
  }

  // Cue hold momentaneo (premi → parte; rilascia → si ferma e torna)
  void deckCueHold(Deck d, boolean on) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/cue_hold", String.valueOf(id), on);
  }

  // Play / Stop
  void deckPlay(Deck d)  { char id = idOf(d); if (id == '?') return; send("/dj3d/deck/play",  String.valueOf(id)); }
  void deckStop(Deck d)  { char id = idOf(d); if (id == '?') return; send("/dj3d/deck/stop",  String.valueOf(id)); }

  // NUOVO: Play specificando la posizione (in secondi)
  void deckPlayAt(Deck d, float seconds) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/play", String.valueOf(id), seconds);
  }

  // BPM target
  void deckSetBPM(Deck d, float bpmTarget) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/bpm", String.valueOf(id), bpmTarget);
  }

  // Loop
  void deckSetLoopIn(Deck d, float sec)     { char id=idOf(d); if(id=='?') return; send("/dj3d/deck/loop_in",     String.valueOf(id), sec); }
  void deckSetLoopOut(Deck d, float sec)    { char id=idOf(d); if(id=='?') return; send("/dj3d/deck/loop_out",    String.valueOf(id), sec); }
  void deckLoopEnable(Deck d, boolean on)   { char id=idOf(d); if(id=='?') return; send("/dj3d/deck/loop_enable", String.valueOf(id), on); }

  // COMPAT: alcuni punti del codice chiamano deckSetLoopEnable(...). Aggiungiamo alias.
  void deckSetLoopEnable(Deck d, boolean on) { deckLoopEnable(d, on); }
  // Overload opzionale per id grezzo
  void deckSetLoopEnable(char id, boolean on) { send("/dj3d/deck/loop_enable", String.valueOf(id), on); }

  // Volume cuffia file singolo
  void deckCueVolume(Deck d, float vol01) {
    char id = idOf(d); if (id == '?') return;
    send("/dj3d/deck/cue_volume", String.valueOf(id), constrain(vol01, 0, 1));
  }

  // Uscite cuffie (hw out index)
  void phonesOut(int outIdx) { send("/dj3d/phones/out", outIdx); }

  // Analisi manuale JSON
  void loadAnalysis(String path) { send("/dj3d/load_analysis", path); }

  // Utility / FX
  void randomAz()      { send("/dj3d/random_az"); }
  void shuffleLfo()    { send("/dj3d/shuffle_lfo"); }
  void addReverb()     { send("/dj3d/add_reverb"); }
  void switchDecoder(String t) { send("/dj3d/switch_decoder", t); } // "simple"/"binaural"

  // Record ambisonics
  void record(boolean on, String pathOrNull) {
    if (pathOrNull == null || pathOrNull.isEmpty()) send("/dj3d/record", on);
    else send("/dj3d/record", on, pathOrNull);
  }

  // Free all
  void freeAll() { send("/dj3d/free_all"); }

  // =========================================================
  // RICEZIONE (SuperCollider → Processing)
  // =========================================================
  private void plugIncomings() {
    try {
      // Stato generale
      osc.plug(this, "onHello",        "/dj3d/hello");        // (int langPort, int order, int numChannels)
      osc.plug(this, "onDecoder",      "/dj3d/decoder");      // (String type)
      osc.plug(this, "onReverb",       "/dj3d/reverb");       // (int on)
      osc.plug(this, "onPhonesOut",    "/dj3d/phones_out");   // (int outIdx)
      osc.plug(this, "onGlobalBPM",    "/dj3d/global_bpm");   // (float bpm)
      osc.plug(this, "onRun",          "/dj3d/run");          // (int on)
      osc.plug(this, "onRecord",       "/dj3d/record");       // (int on, String path)
      osc.plug(this, "onFreed",        "/dj3d/freed");        // ()
      osc.plug(this, "onWarn",         "/dj3d/warn");         // (Object any)
      osc.plug(this, "onError",        "/dj3d/error");        // (Object any)

      // Caricamenti / analisi
      osc.plug(this, "onStemsLoaded",  "/dj3d/stems_loaded");     // (String deckId, String stemsDir, int count)
      osc.plug(this, "onTrackLoaded",  "/dj3d/track_loaded");     // (int idx, String filename, int numCh, int isPerc, String deckId)
      osc.plug(this, "onAnalysisLoaded","/dj3d/analysis_loaded"); // (String path, int matched, int total)
      osc.plug(this, "onFileFinalized","/dj3d/file_finalized");   // (String base, int nOnsets, float bpm)
      osc.plug(this, "onPlayEnabled",  "/dj3d/play_enabled");     // (int enabled, int finalizedCount, int expected)

      // Deck stato / cue / loop / bpm / rate
      osc.plug(this, "onDeckState",    "/dj3d/deck/state");       // (String deckId, int state)
      osc.plug(this, "onDeckCueLoaded","/dj3d/deck/cue_loaded");  // (String deckId, String path)
      osc.plug(this, "onDeckCueState", "/dj3d/deck/cue_state");   // (String deckId, int state)
      osc.plug(this, "onDeckCueVolume","/dj3d/deck/cue_volume");  // (String deckId, float vol)
      osc.plug(this, "onDeckCuePos",   "/dj3d/deck/cue_pos");     // (String deckId, float sec)
      osc.plug(this, "onDeckLoopIn",   "/dj3d/deck/loop_in");     // (String deckId, float sec)
      osc.plug(this, "onDeckLoopOut",  "/dj3d/deck/loop_out");    // (String deckId, float sec)
      osc.plug(this, "onDeckLoopEnable","/dj3d/deck/loop_enable");// (String deckId, int on)
      osc.plug(this, "onDeckBPM",      "/dj3d/deck/bpm");         // (String deckId, float target, float ref, float rate)
      osc.plug(this, "onDeckRate",     "/dj3d/deck/rate");        // (String deckId, float rate) (feedback speed)
      osc.plug(this, "onSeekAck",      "/dj3d/deck/seek_ack");    // (String deckId, float sec)

      // Crossfader
      osc.plug(this, "onCrossfader",   "/dj3d/crossfader");       // (float x, float gA, float gB)

      // Volume & speed (feedback eventuale)
      osc.plug(this, "onDeckVolumeFB", "/dj3d/deck/volume");      // (String deckId, float vol)
      // (speed già coperto da /dj3d/deck/rate se inviato da SC)
    } catch (Exception e) {
      app.println("[OscBridge][ERR] plugIncomings: " + e);
      e.printStackTrace();
    }
  }

  // ============================
  // CALLBACKS
  // ============================
  public void onHello(int langPort, int order, int numCh) {
    receivedHello = true;
    connected = true;
    log("SC hello: port=" + langPort + " order=" + order + " ch=" + numCh);
  }
  public void onDecoder(String type) { log("decoder: " + type); }
  public void onReverb(int on) { log("reverb: " + on); }
  public void onPhonesOut(int outIdx) { log("phones out: " + outIdx); }
  public void onGlobalBPM(float bpm) { log("global BPM: " + bpm); }
  public void onRun(int on) { log("run: " + on); }
  public void onRecord(int on, String path) { log("record: " + on + " path=" + path); }
  public void onFreed() { log("freed all"); }
  public void onWarn(Object a) { log("WARN: " + a); }
  public void onError(Object a) { log("ERR: " + a); }

  public void onStemsLoaded(String deckId, String stemsDir, int count) {
    log("stems loaded deck=" + deckId + " count=" + count + " dir=" + stemsDir);
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
    if (d != null && d.playBtn != null) {
      d.playBtn.setPlaying(state != 0);
    }
    log("deck/state " + deckId + " -> " + state);
  }
  public void onDeckCueLoaded(String deckId, String path) {
    log("cue loaded " + deckId + " path=" + path);
  }
  public void onDeckCueState(String deckId, int state) {
    log("cue state " + deckId + " -> " + state);
  }
  public void onDeckCueVolume(String deckId, float v) {
    log("cue volume " + deckId + " -> " + v);
  }
  public void onDeckCuePos(String deckId, float sec) {
    log("cue pos " + deckId + " -> " + nf(sec, 0, 3));
  }
  public void onDeckLoopIn(String deckId, float sec) {
    log("loop in " + deckId + " -> " + sec);
  }
  public void onDeckLoopOut(String deckId, float sec) {
    log("loop out " + deckId + " -> " + sec);
  }
  public void onDeckLoopEnable(String deckId, int on) {
    log("loop enable " + deckId + " -> " + on);
  }
  public void onDeckBPM(String deckId, float target, float ref, float rate) {
    log("deck bpm " + deckId + " target=" + target + " ref=" + ref + " rate=" + rate);
  }
  public void onDeckRate(String deckId, float rate) {
    log("deck rate feedback " + deckId + " -> " + rate);
  }
  public void onCrossfader(float x, float gA, float gB) {
    log("crossfader x=" + nf(x,0,3) + " gA=" + nf(gA,0,3) + " gB=" + nf(gB,0,3));
    if (center != null) center.setCrossfader(x);
  }
  public void onDeckVolumeFB(String deckId, float v) {
    log("deck volume FB " + deckId + " -> " + v);
    // Se vuoi aggiornare fader grafico (occhio a loop di feedback):
    // if(center != null) { if(deckId.equals("A")) center.setVolumeA(v); else if(deckId.equals("B")) center.setVolumeB(v); }
  }
  public void onSeekAck(String deckId, float sec) {
    log("seek ack " + deckId + " -> " + nf(sec,0,3));
  }

  // =========================================================
  // UTILITA' DI STATO
  // =========================================================
  boolean isConnected() { return connected && receivedHello; }
  void setDebug(boolean d) { debug = d; }
}
