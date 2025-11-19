//////////////////////////////////////////////////////////////
// DJ 3D — 2 Decks + Crossfader + Stems loader (JSON feats) //
// Azimuth = LFO; Flux -> LFO rate; Contrast -> Elevation°  //
// NO GUI — OSC control + reads analysis from JSON          //
//                                                          //
// LOAD SPEC:                                               //
// Processing -> /dj3d/deck/load_file <A|B> <filePath>      //
// SC:                                                      //
//  - prepares that file for headphones (dry, no ambi)      //
//  - finds folder: <parent>/stems/<basename-no-ext>        //
//  - loads all audio stems in that folder through encoders //
//  - loads JSON in that folder with features per stem      //
//                                                          //
// DECK TRANSPORT (sync per deck):                          //
//  - /dj3d/deck/play <A|B>                                 //
//  - /dj3d/deck/stop <A|B>                                 //
//  - /dj3d/deck/cue_hold <A|B> <0|1>                       //
//  - /dj3d/deck/set_cue <A|B> <seconds>                    //
//  - /dj3d/deck/bpm <A|B> <targetBPM>                      //
//  - /dj3d/deck/loop_in <A|B> <seconds>                    //
//  - /dj3d/deck/loop_out <A|B> <seconds>                   //
//  - /dj3d/deck/loop_enable <A|B> <0|1>                    //
//////////////////////////////////////////////////////////////
// vedi i device
ServerOptions.outDevices;   // o: ServerOptions.devices;

// imposta solo l'output
Server.default.options.outDevice_("Altoparlanti MacBook Pro");
Server.default.options.outDevice_("IT663x1");
Server.default.options.numOutputBusChannels = 8;  // quante uscite fisiche userai
// (alcune build richiedono anche:)
Server.default.options.numOutputChannels = 8;
(
// ================== SETTINGS ==================
~order = 3;
~numChannels = ((~order + 1) ** 2).asInteger;   // 3rd order -> 16 channels
~pluginNames = (
    encoder: "StereoEncoder",
    binauralDecoder: "BinauralDecoder",
    simpleDecoder: "SimpleDecoder",
    reverb: "FdnReverb"
);
~orderOut = 3;
~outChannels = 8;  // numero di canali di uscita desiderati per il simpleDecoder

// IEM StereoEncoder params: azimuth=6, elevation=7
~encoderAzParam = 6;
~encoderElParam = 7;

~meterRate = 20; // Hz per l’aggiornamento dei livelli encoder

// Decoder selection: 'binaural' or 'simple'
~decoderType = \simpleDecoder;

// === Processing / OSC peer ===
~processingHost = "127.0.0.1";
~processingPort = 57121;          // Porta di Processing
~processing     = NetAddr(~processingHost, ~processingPort);

// Porta OSC di SC (default 57120)
~scOscInPort = NetAddr.langPort;

// Uscite cuffie (hw out index). Se usi interfacce multi-out, imposta p.es. 2 per usare out 2-3
~phonesOut = 10;  // canale di partenza (stereo -> out, out+1)

// Cartella di default (non usata nel nuovo load, lasciata per compatibilità)
~defaultFolder = "";

~files = Dictionary.new;
~filesFinalizedCount = 0;
~expectedFiles = 0;
~globalBPM = nil;

// Dati di analisi da Python (stessa logica di ambisonics_onset)
~files = Dictionary.new;    // name -> entry (bpm, chunks, arrays, timeline)
~expectedFiles = 0;
~filesFinalizedCount = 0;
~globalBPM = nil;

// Trova una traccia caricata a partire dal basename (es. "drums.wav")
~trackByBaseName = { |base|
    ~tracks.detect { |x|
        var p = x[\path];
        p.notNil and: { PathName(p).fileName == base }
    }
};

// Crea l’entry per un file di analisi se non esiste
~ensureFileEntry = { |name|
    if(~files[name].isNil) {
        ~files[name] = (
            bpm: nil,
            chunks: (
                times:    Dictionary.new,
                pos:      Dictionary.new,
                flux:     Dictionary.new,
                contrast: Dictionary.new
            ),
            onsetTimes:    #[],
            onsetPos:      #[],
            onsetFlux:     #[],
            onsetContrast: #[],
            timeline: #[],
            routine: nil,
            finalized: false
        );
    };
};

// Ricostruisce un array a partire dai chunk (dict: idx -> valori[])
~rebuildArrayFromChunks = { |dict|
    var keys = dict.keys.asArray.sort;
    var acc  = Array.new;
    keys.do { |k| acc = acc.addAll(dict[k]) };
    acc
};

// Ricostruisce la timeline completa quando tutti i chunk del file sono arrivati
~finalizeFile = { |name|
    var e = ~files[name];
    var ch, n;

    if(e.isNil) {
        ("[SC][WARN] finalize: missing entry for '%'".format(name)).postln;
        ^nil;
    };

    ch = e[\chunks];

    e[\onsetTimes]    = ~rebuildArrayFromChunks.(ch[\times]);
    e[\onsetPos]      = ~rebuildArrayFromChunks.(ch[\pos]);
    e[\onsetFlux]     = ~rebuildArrayFromChunks.(ch[\flux]);
    e[\onsetContrast] = ~rebuildArrayFromChunks.(ch[\contrast]);

    n = [
        e[\onsetTimes].size,
        e[\onsetPos].size,
        e[\onsetFlux].size,
        e[\onsetContrast].size
    ].minItem;

    if(n <= 0) {
        ("[SC][WARN] empty timeline for '%'".format(name)).postln;
        ^nil;
    };

    e[\onsetTimes]    = e[\onsetTimes].copyRange(0, n-1);
    e[\onsetPos]      = e[\onsetPos].copyRange(0, n-1);
    e[\onsetFlux]     = e[\onsetFlux].copyRange(0, n-1);
    e[\onsetContrast] = e[\onsetContrast].copyRange(0, n-1);

    e[\timeline] = Array.fill(n, { |i|
        (
            time:     e[\onsetTimes][i],
            beat:     e[\onsetPos][i],
            flux:     e[\onsetFlux][i],
            contrast: e[\onsetContrast][i]
        )
    });

    e[\finalized] = true;
    ~files[name] = e;

    ~filesFinalizedCount = ~filesFinalizedCount + 1;

    ("[SC] Finalized file '%': N=% | BPM=%"
        .format(name, n, (e[\bpm] ? "nil"))).postln;

    // stampa qualche evento per debug
    e[\timeline].copyRange(0, (n-1).clip(0, 7)).do(_.postln);
};

// ================== GLOBALS ==================
~ambiMasterBus = nil;
~ambiMasterGroup = nil;
~ambiMasterFXGroup = nil;
~decoder = nil;        // VSTPluginController
~ambiReverb = nil;

~tracks = List.new;    // lista di tracce (Event) caricate (stems)
~recorder = nil;
~recording = false;

// stato run globale (compat)
~isPlaying = false;

// ================== 2 DECKS + CROSSFADER ==================
~decks = ( A: (), B: () );
~crossfaderVal = 0.5;        // 0 = full A, 1 = full B (equal-power)

// ================== HELPERS ==================
~db = { |x| (20 * log10(max(x, 1e-9))).clip(-96, 24) };
~mkGroupChain = { |target| Group.new(target: target ?? { RootNode(s) }) };

// === Periodo di controllo (sec), calcolato al volo ===
~ctrlPeriodSec = { s.options.blockSize / s.sampleRate };

// amp base per evitare clip
~computeBaseAmp = {
    var count;
    count = ~tracks.select({ |t| t[\deck].notNil }).size;
    1 / max(1, count + 1)
};

// Stable percussion detection via filename
~isPercussionTrack = { |path|
    var filename = PathName(path).fileName.asString;
    var lower = filename.toLower;
    (lower.contains("drum") or: { lower.contains("kick") } or: { lower.contains("perc") } or: { lower.contains("bd") })
};

// ================== SYNTHDEFS ==================
SynthDef(\binauralDecoder, { | bus, out = 0 |
    var n = ~numChannels;
    Out.ar(out, VSTPlugin.ar(In.ar(bus, n), 2));
}).add;

// Sostituisci il simpleDecoder con questa versione
SynthDef(\simpleDecoder, { | bus, out = 0 |
    var n     = ~numChannels;              // HOA in ingresso
    var outs  = ~outChannels.asInteger;    // numero uscite fisiche (costante al build)
    var inS   = In.ar(bus, n);
    var dec   = VSTPlugin.ar(inS, outs);   // QUI outs è un intero, NON un Control
    Out.ar(out, dec);
}).add;

SynthDef(\stereoEncoder, { | bus = 0 |
    var n = ~numChannels;
    ReplaceOut.ar(bus, VSTPlugin.ar(In.ar(bus, 2), n));
}).add;

SynthDef(\ambiFX, { | bus = 0, bypass = 0 |
    var n = ~numChannels;
    ReplaceOut.ar(bus, VSTPlugin.ar(In.ar(bus, n), n, bypass));
}).add;

SynthDef(\ambiThrow, { | from, to |
    var n = ~numChannels;
    Out.ar(to, In.ar(from, n));
}).add;

// stereo player with trigger + startPos (for deck sync + cue/loop)
SynthDef(\stereoPlayer, { | out=0, buf=0, rate=1, amp=1, trig=0, startPos=0 |
    var sig = PlayBuf.ar(2, buf, BufRateScale.kr(buf) * rate, trig, startPos, loop: 1);
    Out.ar(out, sig * amp);
}).add;

// mono -> stereo player with trigger + startPos
SynthDef(\monoPlayer, { | out=0, buf=0, rate=1, amp=1, trig=0, startPos=0 |
    var sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * rate, trig, startPos, loop: 1);
    Out.ar(out, sig.dup * amp);
}).add;

// cuffie: player stereo diretto a uscite hw (no ambi)
SynthDef(\cuePlayer, { | out=0, buf=0, rate=1, amp=1, trig=0, startPos=0 |
    var sig = PlayBuf.ar(2, buf, BufRateScale.kr(buf) * rate, trig, startPos, loop: 1);
    Out.ar(out, sig * amp);
}).add;

// Azimuth LFO (output 0..1)
SynthDef(\azLFO, { | outBus=0, rate=0.5 |
    var ctrl = LFNoise1.kr(rate).range(0, 1);
    Out.kr(outBus, ctrl);
}).add;

// Elevation smoother (gradi -> normalized IEM)
SynthDef(\elevSmoother, { | outBus=0, targetDeg=90, lag=0.15 |
    var deg = VarLag.kr(targetDeg.clip(0, 180), lag);
    var norm = deg.linlin(0, 180, 0.5, 0.75);
    Out.kr(outBus, norm);
}).add;

SynthDef(\encoderMeter, { | inbus=0, tid=0, rate=20 |
    var sig = Mix(In.ar(inbus, 2));         // stereo fisso
    var amp = Amplitude.kr(sig, 0.05, 0.5).clip(0, 1);
    SendTrig.kr(Impulse.kr(rate), tid, amp);
}).add;

// ================== SERVER BOOT ==================
s.waitForBoot({
    "Server booted. Scanning plugins…".postln;
    VSTPlugin.search(verbose: false);


    ~processing.sendMsg('/dj3d/hello', ~scOscInPort, ~order, ~numChannels);
});

// ================== MASTER AMBISONIC ==================
~setupAmbiMaster = {
    var synthName, pluginName, outCh;

    ~ambiMasterBus !? { ~ambiMasterBus.free };
    ~ambiMasterBus = Bus.audio(s, ~numChannels);
    ~ambiMasterGroup = Group.head(s);
    ~decoder !? { ~decoder.free };

    if(~decoderType == \simple) {
        synthName  = \simpleDecoder;
        pluginName = ~pluginNames[\simpleDecoder];
        outCh      = ~outChannels.max(8);
    } {
        synthName  = \binauralDecoder;
        pluginName = ~pluginNames[\binauralDecoder];
        outCh      = 8;
    };

    // NOTA: niente \outCh qui
    ~decoder = VSTPluginController(
        Synth(synthName, [\bus, ~ambiMasterBus, \out, 0],
            target: ~ambiMasterGroup, addAction: \addToTail)
    ).open(pluginName);

    ~ambiMasterFXGroup = Group.before(~decoder.synth);

    ("[SC] Ambi master ready: HOA=%ch -> OUT=%ch | decoder=% | plugin=%"
        .format(~numChannels, outCh, ~decoderType, pluginName)).postln;

    ~processing.sendMsg('/dj3d/decoder', (~decoderType.asString));
};

~switchDecoder = { |newType|
    var target = newType.asString.toLower.asSymbol;
    if(target != \simple and: { target != \binaural }) {
        "[SC] Unknown decoder type: %".format(target).warn; ^nil;
    };
    if(target == ~decoderType) {
        ("[SC] Decoder già attivo (%), nessuno switch.".format(target)).postln;
        ^nil;
    };
    ("[SC] Switching decoder: % -> %".format(~decoderType, target)).postln;
    ~decoderType = target;
    ~setupAmbiMaster.();
};

~addMasterReverb = {
    ~ambiReverb !? { ~ambiReverb.free };
    ~ambiReverb = VSTPluginController(
        Synth(\ambiFX, [\bus, ~ambiMasterBus],
            target: ~ambiMasterFXGroup, addAction: \addToHead)
    ).open(~pluginNames[\reverb]);
    "Added ambisonic FdnReverb".postln;
    ~processing.sendMsg('/dj3d/reverb', 1);
};

// ================== TRACK (STEM) CREATION ==================
~makeTrack = { |path, idx, deckId = nil|
    // ==============================
    // Variabili locali (tutte inizializzate)
    // ==============================
    var file        = nil;
    var numCh       = 0;
    var ambiBus     = nil;
    var grp         = nil;
    var lfoBus      = nil;
    var elBus       = nil;
    var elSmooth    = nil;
    var isPerc      = false;
    var synthName   = \stereoPlayer;
    var tr          = nil;
    var buf         = nil;

    // ==============================
    // Verifica file e canali
    // ==============================
    file = SoundFile.openRead(path);
    numCh = file.numChannels;
    if((numCh != 1) and: (numCh != 2)) {
        ("[WARN] % is %ch, expected mono or stereo; skipping."
            .format(PathName(path).fileName, numCh)).warn;
        file.close;
        ^nil;
    };
    file.close;

    // ==============================
    // Allocazioni base
    // ==============================
    ambiBus = Bus.audio(s, ~numChannels);
    grp     = Group.before(~ambiMasterGroup);    // gruppo della traccia (prima del decoder master)
    lfoBus  = Bus.control(s, 1);                 // bus controllo (azimuth LFO)
    elBus   = Bus.control(s, 1);                 // bus elevation smoothing

    // Percussione (filename based)
    isPerc = ~isPercussionTrack.(path);
    ("[SC] Track: % | isPerc: % | deck: %"
        .format(PathName(path).fileName, isPerc, deckId)).postln;

    // Elevation smoothing synth
    elSmooth = Synth.tail(grp, \elevSmoother, [
        \outBus,     elBus,
        \targetDeg,  (isPerc).if({ 0 }, { 90 }),
        \lag,        0.15
    ]);

    // Player synth name (mono -> monoPlayer, stereo -> stereoPlayer)
    synthName = (numCh == 1).if({ \monoPlayer }, { \stereoPlayer });

    // ==============================
    // Event traccia (tutti i campi inizializzati)
    // ==============================
    tr = ();
    tr[\index]     = idx;
    tr[\path]      = path;
    tr[\deck]      = deckId;
    tr[\numCh]     = numCh;

    tr[\buf]       = nil;
    tr[\group]     = grp;
    tr[\ambiBus]   = ambiBus;
    tr[\player]    = nil;
    tr[\encoder]   = nil;

    tr[\lfoBus]    = lfoBus;
    tr[\lfoSynth]  = nil;
    tr[\lfoActive] = false;

    tr[\elBus]     = elBus;
    tr[\elSmooth]  = elSmooth;
    tr[\isPerc]    = isPerc;

    tr[\deckIdx]   = nil;   // verrà impostato in ~loadStemsFolderToDeck
    tr[\meter]     = nil;   // verrà creato dopo (non conosciamo ancora trigID tid)
	tr[\meterTid]  = nil;   // <-- AGGIUNGI QUESTA RIGA

    // ==============================
    // Funzioni helper salvate nel track Event
    // ==============================
    tr[\setAz] = { |az|      // Imposta azimuth direttamente (se non percussivo)
        tr[\encoder].notNil.if {
            if(tr[\isPerc]) {
                tr[\encoder].set(~encoderAzParam, 0.5); // fisso perc
            }{
                tr[\encoder].set(~encoderAzParam, az);
            };
        };
    };

    tr[\mapAzToLfo] = {
        if(tr[\isPerc]) {
            ("[SC] Perc track, skip Az LFO mapping: %"
                .format(PathName(tr[\path]).fileName)).postln;
        }{
            tr[\encoder].notNil.if {
                tr[\encoder].map(~encoderAzParam, tr[\lfoBus]);
            };
        };
    };

    tr[\unmapAz] = {
        tr[\encoder].notNil.if {
            tr[\encoder].unmap(~encoderAzParam);
        };
    };

    tr[\setLfoSynth] = { |synth|
        tr[\lfoSynth] = synth;
    };

tr[\free] = {
    tr[\lfoSynth].notNil.if { tr[\lfoSynth].free; tr[\lfoSynth] = nil };
    tr[\elSmooth].notNil.if { tr[\elSmooth].free; tr[\elSmooth] = nil };
    tr[\meter].notNil.if { tr[\meter].free; tr[\meter] = nil };
    tr[\encoder].notNil.if { tr[\encoder].free; tr[\encoder] = nil };
    tr[\player].notNil.if { tr[\player].free; tr[\player] = nil };
    tr[\buf].notNil.if { tr[\buf].free; tr[\buf] = nil };
    tr[\ambiBus].notNil.if { tr[\ambiBus].free; tr[\ambiBus] = nil };
    tr[\lfoBus].notNil.if { tr[\lfoBus].free; tr[\lfoBus] = nil };
    tr[\elBus].notNil.if { tr[\elBus].free; tr[\elBus] = nil };
    tr[\group].notNil.if { tr[\group].free; tr[\group] = nil };
};

    // ==============================
    // Caricamento buffer + creazione player + encoder + throw
    // ==============================
    buf = Buffer.readChannel(
        s,
        path,
        channels: (numCh == 1).if({ [0] }, { [0, 1] }),
action: { |b|
    {
        tr[\buf] = b;

        // Player all'inizio del group
        tr[\player] = Synth.head(grp, synthName, [
            \out,      ambiBus,
            \buf,      b,
            \rate,     1,
            \amp,      0,
            \trig,     0,
            \startPos, 0
        ]);

        // ========================================
        // METER: dopo il player, prima dell'encoder
        // ========================================
        if (tr[\meterTid].notNil) {
            tr[\meter].notNil.if { tr[\meter].free };  // libera vecchio se esiste
            tr[\meter] = Synth.after(tr[\player], \encoderMeter, [
                \inbus, ambiBus.index,
                \tid,   tr[\meterTid],
                \rate,  ~meterRate
            ]);
        };

        // Encoder (tail) + parametri
        tr[\encoder] = VSTPluginController(
            Synth.tail(grp, \stereoEncoder, [\bus, ambiBus])
        ).open(~pluginNames[\encoder], action: { |ctrl|
            ctrl.set(~encoderAzParam, (tr[\isPerc]).if({ 0.5 }, { 1.0.rand }));
            if (tr[\isPerc]) {
                ctrl.set(~encoderElParam, 0.5);
            } {
                ctrl.map(~encoderElParam, elBus);
            };
        });

        // Throw ambisonico
        Synth.tail(grp, \ambiThrow, [\from, ambiBus, \to, ~ambiMasterBus]);

        // Notifica Processing
        ~processing.sendMsg('/dj3d/track_loaded',
            tr[\index],
            PathName(tr[\path]).fileName,
            tr[\numCh],
            tr[\isPerc].asInteger,
            (deckId ?? "-").asString
        );
    }.defer;
}
    );

    // ==============================
    // Ritorna l'Event traccia
    // ==============================
    tr;
};

// ================== FOLDER (STEMS) LOADER ==================
~loadStemsFolderToDeck = { |stemsDir, deckId|
    var pn, exts, files, baseIdxStart, newTracks;
    pn = PathName(stemsDir);
    exts = [".wav", ".aiff", ".aif", ".flac"];

    files = pn.files.collect(_.fullPath).select { |p|
        var lower = p.asString.toLower;
        exts.any { |ext| lower.endsWith(ext) }
    }.sort;

    if(files.isEmpty) {
        "[ERROR] No valid audio stems in folder: %".format(stemsDir).warn;
        ~processing.sendMsg('/dj3d/error', "no_audio_files_in_stems", stemsDir);
        ^[];
    }{
        baseIdxStart = ~tracks.size; // mantieni progressivo
        newTracks = files.collect { |f, i|
            var t = ~makeTrack.(f, baseIdxStart + i, deckId);
            if(t.notNil) { ~tracks.add(t) };
            t
        }.select(_.notNil);
        "Loaded % stems into deck %.".format(newTracks.size, deckId).postln;
        ~processing.sendMsg('/dj3d/stems_loaded', deckId.asString, stemsDir, newTracks.size);
        ^newTracks
    };
};

// ================== RUN CONTROL (compat) ==================
~startRun = {

    ~applyDeckStemsAmps.();

    ~files.keys.do { |name|
        var e = ~files[name];
        if(e.notNil and: { e[\finalized] }) {
            (e[\routine].isNil).if { ~startAutomationFor.(name) };
        };
    };

    ~isPlaying = true;
    ("[SC] Run started.").postln;
    ~processing.sendMsg('/dj3d/run', 1);
};

~stopRun = {
    ~tracks.do { |t|
        t[\player].notNil.if { t[\player].set(\amp, 0) };
        t[\lfoSynth].notNil.if { t[\lfoSynth].free; t[\lfoSynth] = nil; t[\lfoActive] = false };
    };

    ~files.keys.do { |name|
        var e = ~files[name];
        e.notNil.if {
            e[\routine].notNil.if { e[\routine].stop; e[\routine] = nil };
        };
    };

    ~isPlaying = false;
    ("[SC] Run stopped.").postln;
    ~processing.sendMsg('/dj3d/run', 0);
};

// RECORD (Ambisonic bus)
~toggleRecord = { |state=1, path=nil|
    if(state.asBoolean and: { ~recording.not }) {
        var filePath;
        filePath = path ? {
            var timeStamp = Date.getDate.stamp;
            "~/Music/ambisonic-piece-%_o%_%ch.wav".format(timeStamp, ~order, ~numChannels).standardizePath
        };
        ~recorder = Recorder(s);
        ~recorder.record(filePath, ~ambiMasterBus, ~numChannels, ~ambiMasterFXGroup);
        ~recording = true;
        "Recording ambisonics to: %".format(filePath).postln;
        ~processing.sendMsg('/dj3d/record', 1, filePath);
    }{
        ~recorder !? { _.stopRecording };
        ~recording = false;
        "Recording stopped.".postln;
        ~processing.sendMsg('/dj3d/record', 0);
    }
};

// ================== AUTOMATION (timeline) ==================
~startAutomationFor = { |name|
    var t, times, flux, contrast, routine, e, maxWait, waited, dt, fNorm, rate, elDeg;
    e = ~files[name];
    if(e.isNil) { ("[SC][ERR] No entry for '%'".format(name)).warn; ^nil };

    t = ~trackByBaseName.(name);
    if(t.isNil) { ("[SC][ERR] No loaded track for '%'".format(name)).warn; ^nil };

    e[\routine].notNil.if { e[\routine].stop; e[\routine] = nil };

    routine = Routine({
        maxWait = 5.0; waited = 0.0;
        while({ t[\encoder].isNil and: { waited < maxWait } }, { 0.1.wait; waited = waited + 0.1; });
        if(t[\encoder].isNil) { ("[SC][ERR] Encoder not ready for '%'".format(name)).warn; ^thisThread.stop };

        if((t[\lfoSynth].isNil) and: { t[\isPerc].not }) {
            t[\lfoSynth] = Synth(\azLFO, [\outBus, t[\lfoBus], \rate, 0.5]);
            t[\mapAzToLfo].();
            t[\lfoActive] = true;
        };

        times = e[\onsetTimes];
        flux = e[\onsetFlux];
        contrast = e[\onsetContrast];

        times.do { |tAbs, i|
            dt = (i == 0).if({ tAbs }, { (tAbs - times[i-1]).max(0.0) });
            dt.wait;

            fNorm = flux.wrapAt(i).clip(0, 1);
            rate  = fNorm.linexp(0.02, 0.8, 0.15, 3.0);
            if(t[\isPerc].not) {
                t[\lfoSynth].notNil.if { t[\lfoSynth].set(\rate, rate) };
            }{
                t[\encoder].notNil.if { t[\encoder].set(~encoderAzParam, 0.5) };
            };

            elDeg = contrast.wrapAt(i).linlin(0, 1, 0, 180);
            if(t[\isPerc].not) {
                t[\elSmooth].notNil.if { t[\elSmooth].set(\targetDeg, elDeg) };
            }{
                t[\encoder].notNil.if { t[\encoder].set(~encoderElParam, 0.5) };
                t[\elSmooth].notNil.if { t[\elSmooth].set(\targetDeg, 0) };
            };
        };
    });
    e[\routine] = routine;
    routine.play(AppClock);
};


// ================== 2 DECKS: LOGICA STEMS + CUE + TRANSPORT ==================
~deckCollectStems = { |id|
    ~tracks.select { |t| t[\deck] == id }
};

~deckComputeRefBPM = { |id|
    var stems, bpmVal;
    // preferisci bpm dalle analisi dei stems del deck; altrimenti global; fallback 120
    stems = ~deckCollectStems.(id);
    bpmVal = stems.collect { |t|
        var base = PathName(t[\path]).fileName;
        var e = ~files[base];
        e.notNil.if({ e[\bpm] }, { nil });
    }.detect(_.notNil);
    (bpmVal ? ~globalBPM ? 120.0).asFloat
};

~deckApplyRate = { |id|
    var d = ~decks[id], stems = ~deckCollectStems.(id);
    if(d.isNil or: { stems.isEmpty }) { ^nil };
    s.makeBundle(s.latency, {
        stems.do { |t| t[\player].notNil.if { t[\player].set(\rate, d[\rate].clip(0.25, 4.0)) } };
    });
};

~deckRetriggerAll = { |id, startSam|
    var stems, dt;
    stems = ~deckCollectStems.(id);
    if(stems.isEmpty) { ^nil };

    s.makeBundle(s.latency, {
        stems.do { |t|
            t[\player].notNil.if {
                t[\player].set(\startPos, startSam.max(0).asInteger, \trig, 0);
            };
        };
    });

    dt = ~ctrlPeriodSec.().max(1.0 / s.sampleRate);
    s.makeBundle(s.latency + dt, {
        stems.do { |t|
            t[\player].notNil.if { t[\player].set(\trig, 1) };
        };
    });
};

~deckStartFrom = { |id, startSam|
    var d = ~decks[id]; if(d.isNil) { ^nil };
    d[\playing] = true;
    ~deckRetriggerAll.(id, startSam);
    ~applyDeckStemsAmps.();
    ~deckEnsureLoopRoutine.(id);
    ~processing.sendMsg('/dj3d/deck/state', id.asString, 1);
};

~deckEnsureLoopRoutine = { |id|
    var d, loopLenSam, waitSecsFunc, t;
    d = ~decks[id];
    d[\loopRoutine].notNil.if { d[\loopRoutine].stop; d[\loopRoutine] = nil };
    if(d[\loopEnabled] and: { d[\playing] } and: { d[\loopOutSam] > d[\loopInSam] }) {
        loopLenSam = d[\loopOutSam] - d[\loopInSam];
        waitSecsFunc = { loopLenSam / (d[\rate].clip(0.001, 100.0) * s.sampleRate) };
        d[\loopRoutine] = Routine({
            // initial alignment: already triggered at loopIn elsewhere
            loop {
                t = waitSecsFunc.();
                t.max(0.001).wait;
                if(d[\loopEnabled].not or: { d[\playing].not }) { ^thisThread.stop };
                ~deckRetriggerAll.(id, d[\loopInSam]);
            }
        }).play(AppClock);
    };
};

~initDecks = {
    ['A', 'B'].do { |id|
        var d;
        d = ();
        d[\id]       = id;
        d[\playing]  = false;    // stems playing state
        d[\volume]   = 1.0;      // trim deck 0..1
        d[\gain]     = 0.0;      // from crossfader
        d[\rate]     = 1.0;      // playback rate factor
        d[\bpmRef]   = 120.0;    // reference bpm
        d[\bpmTarget]= 120.0;    // target bpm
        // Transport positions in samples (frame index)
        d[\cuePosSam]   = 0;
        d[\loopInSam]   = 0;
        d[\loopOutSam]  = 0;     // 0 means unset; will be set to min buffer length on enable
        d[\loopEnabled] = false;
        d[\loopRoutine] = nil;

        // CUE (file singolo per cuffie)
        d[\cueGroup] = Group.head(s);
        d[\cueBuf]   = nil;
        d[\cuePlayer]= nil;
        d[\cueVol]   = 0.8;
        d[\cueOut]   = ~phonesOut;

        ~decks.put(id, d);
    };
    ~setCrossfader.(~crossfaderVal ?? { 0.5 });
};

// Equal-power crossfader
~setCrossfader = { |x|
    var xa, gA, gB;
    xa = x.clip(0, 1);
    gA = cos(xa * (pi/2));
    gB = sin(xa * (pi/2));
    ~crossfaderVal = xa;
    ~decks['A'][\gain] = gA;
    ~decks['B'][\gain] = gB;
    ~applyDeckStemsAmps.();
    ~processing.sendMsg('/dj3d/crossfader', xa, gA, gB);
};

// Applica i gain deck agli stems assegnati
~applyDeckStemsAmps = {
    var baseAmp;
    baseAmp = ~computeBaseAmp.();
    ~tracks.do { |t|
        var id, d, amp;
        id = t[\deck];
        if(id.notNil) {
            d = ~decks[id];
            amp = (d[\playing].asBoolean).if({ baseAmp * d[\gain] * d[\volume] }, { 0 });
            t[\player].notNil.if { t[\player].set(\amp, amp) };
        }{
            t[\player].notNil.if { t[\player].set(\amp, 0) };
        };
    };
};

// Libera stems appartenenti a un deck (prima di un nuovo load)
~deckClearStems = { |id|
    var toRemove, d;

    // Seleziona le tracce da rimuovere
    toRemove = ~tracks.select { |t| t[\deck] == id };

    // Ferma la routine di loop del deck, se attiva
    d = ~decks[id];
    if(d.notNil and: { d[\loopRoutine].notNil }) {
        d[\loopRoutine].stop;
        d[\loopRoutine] = nil;
    };

    // Itera sulle tracce da rimuovere
toRemove.do { |t|
    var base, e;

    // --- INIZIO MODIFICA FONDAMENTALE ---
    // Prima di liberare la traccia, trova e ferma la sua routine di automazione!
    base = PathName(t[\path]).fileName;
    e = ~files[base]; // Trova l'entry di analisi corrispondente

    if(e.notNil and: { e[\routine].notNil }) {
        e[\routine].stop; // Ferma la routine
        e[\routine] = nil;  // Pulisci il riferimento
        ("Stopped automation routine for old stem: %".format(base)).postln;
    };
        // --- FINE MODIFICA FONDAMENTALE ---

        // Ora libera le risorse della traccia in sicurezza
        t[\free].();

        // Rimuovi la traccia dalla lista globale
        ~tracks.remove(t);
    };

    if(toRemove.size > 0) {
        ("Cleared % stems from deck %.".format(toRemove.size, id)).postln;
    }
};

// CUE controls (headphones file)
~deckCueStop = { |id|
    var d;
    d = ~decks[id]; if(d.isNil) { ^nil };
    d[\cuePlayer].notNil.if { d[\cuePlayer].free; d[\cuePlayer] = nil };
    d[\cueBuf].notNil.if { d[\cueBuf].free; d[\cueBuf] = nil };
    ~processing.sendMsg('/dj3d/deck/cue_state', id.asString, 0);
};

// Nuovo: prepara il player cuffie senza avviare la riproduzione
~deckCuePrepare = { |id, buf|
    var d;
    d = ~decks[id]; if(d.isNil) { ^nil };
    d[\cuePlayer].notNil.if { d[\cuePlayer].free };
    d[\cuePlayer] = Synth.head(d[\cueGroup], \cuePlayer, [
        \out, d[\cueOut], \buf, buf, \rate, 1, \amp, 0, \trig, 0, \startPos, 0
    ]);
    ~processing.sendMsg('/dj3d/deck/cue_state', id.asString, 0);
};

~deckCuePlay = { |id, buf|
    var d;
    d = ~decks[id]; if(d.isNil) { ^nil };
    d[\cuePlayer].notNil.if { d[\cuePlayer].free };
    d[\cuePlayer] = Synth.head(d[\cueGroup], \cuePlayer, [
        \out, d[\cueOut], \buf, buf, \rate, 1, \amp, d[\cueVol].clip(0, 1), \trig, 1, \startPos, 0
    ]);
    ~processing.sendMsg('/dj3d/deck/cue_state', id.asString, 1);
};

~deckCueVolume = { |id, vol|
    var d;
    d = ~decks[id]; if(d.isNil) { ^nil };
    d[\cueVol] = vol.clip(0,1);
    d[\cuePlayer].notNil.if { d[\cuePlayer].set(\amp, d[\cueVol]) };
    ~processing.sendMsg('/dj3d/deck/cue_volume', id.asString, d[\cueVol]);
};

~setPhonesOut = { |outIndex|
    ~phonesOut = outIndex.asInteger.max(0);
    ['A','B'].do { |id|
        var d = ~decks[id];
        d[\cueOut] = ~phonesOut;
        if(d[\cuePlayer].notNil and: { d[\cueBuf].notNil }) {
            var buf = d[\cueBuf];
            ~deckCuePlay.(id, buf); // se stava già suonando lo riattacca alla nuova uscita
        };
    };
    ~processing.sendMsg('/dj3d/phones_out', ~phonesOut);
};

// Carica stems per un deck dato un "file" principale; NON avvia più il CUE
~deckLoadFile = { |id, filePath|
    var d, p, parentDir, baseNoExt, stemsDir, newStems, minFrames;

    d = ~decks[id];
    if(d.isNil) {
        "[SC][ERR] Deck % non esiste".format(id).warn;
        ^nil;
    };

    if(File.exists(filePath).not) {
        "[SC][ERR] File non trovato: %".format(filePath).warn;
        ~processing.sendMsg('/dj3d/deck/error', id.asString, "file_not_found", filePath.asString);
        ^nil;
    };

    p = PathName(filePath);
    parentDir = p.pathOnly;
    baseNoExt = p.fileNameWithoutExtension;

    // 1) CUE: carica buffer e PREPARA (non suona)
    ~deckCueStop.(id);
    Buffer.readChannel(s, p.fullPath, channels: [0,1], action: { |b|
        {
            d[\cueBuf] = b;
            ~deckCuePrepare.(id, b); // <-- niente autoplay
            ~processing.sendMsg('/dj3d/deck/cue_loaded', id.asString, p.fullPath);
        }.defer;
    });

    // 2) STEMS: <parent>/stems/<basenameNoExt>
    stemsDir = parentDir +/+ "stems" +/+ baseNoExt;
    if(File.exists(stemsDir).not) {
        "[SC][ERR] Stems folder non trovata: %".format(stemsDir).warn;
        ~processing.sendMsg('/dj3d/deck/error', id.asString, "stems_not_found", stemsDir);
        ^nil;
    };

    // libera stems precedenti del deck
    ~deckClearStems.(id);

    // carica stems nel deck
    newStems = ~loadStemsFolderToDeck.(stemsDir, id);

	~processing.sendMsg('/dj3d/deck/encoders', id.asString, newStems.size);

    // CALCOLA trigID PRIMA di inviare i messaggi
    newStems.do { |t, i|
        var tid;
        t[\deckIdx] = i;

        // Calcola trigID per distinguere deck A (0..99) / B (100..199)
        tid = (id == 'B').if({ 100 + i }, { i });
        t[\meterTid] = tid;  // <-- SALVA qui, prima del buffer action

        // Invia nome encoder (basename del file)
        ~processing.sendMsg('/dj3d/deck/encoder', id.asString, i, PathName(t[\path]).fileName);
    };

    // init transport defaults for this deck
    d[\bpmRef]    = ~deckComputeRefBPM.(id);
    d[\bpmTarget] = d[\bpmRef];
    d[\rate]      = 1.0;
    d[\cuePosSam] = 0;

    if(newStems.notEmpty) {
        minFrames = newStems.collect({ |t| t[\buf].numFrames }).minItem ? 0;
        d[\loopInSam]  = 0;
        d[\loopOutSam] = minFrames;
        d[\loopEnabled]= false;
    };

    ~deckApplyRate.(id);
    ~applyDeckStemsAmps.();

    ~processing.sendMsg('/dj3d/deck/loaded_file', id.asString, p.fullPath, stemsDir);
};

// === AVVIO AUTOMATICO ROUTINE PER DECK ===
~deckStartAllRoutines = { |id|
    var stems, d;
    d = ~decks[id];
    if(d.isNil) { ^nil };

    stems = ~deckCollectStems.(id);
    if(stems.isEmpty) {
        ("[SC] Deck % senza stems — nessuna routine da avviare".format(id)).postln;
        ^nil;
    };

    ("[SC] Avvio routine per deck % (% stems)".format(id, stems.size)).postln;

    stems.do { |t|
        var base, e;
        base = PathName(t[\path]).fileName;
        e = ~files[base];

        if(e.notNil and: { e[\finalized] }) {
            // Se la routine non esiste già, avviala
            if(e[\routine].isNil) {
                ~startAutomationFor.(base);
            };
        }{
            ("[SC][WARN] Analisi non finalizzata per: %".format(base)).warn;
        };
    };
};

~deckPlay = { |id|
    var d, startSam;
    d = ~decks[id];
    if(d.isNil) { ^("[SC][ERR] Deck % non esiste".format(id)).warn };

    // Start from cue or loopIn if loop enabled
    startSam = (d[\loopEnabled]).if({ d[\loopInSam] }, { d[\cuePosSam] });
    ~deckStartFrom.(id, startSam);

    // 🆕 AVVIA ROUTINE DI AUTOMAZIONE
    ~deckStartAllRoutines.(id);
};

~deckStop = { |id|
    var d, stems;
    d = ~decks[id];
    if(d.isNil) { ^("[SC][ERR] Deck % non esiste".format(id)).warn };

    d[\playing] = false;
    d[\loopRoutine].notNil.if { d[\loopRoutine].stop; d[\loopRoutine] = nil };
    ~applyDeckStemsAmps.();

    // 🆕 FERMA ROUTINE DI AUTOMAZIONE
    stems = ~deckCollectStems.(id);
    stems.do { |t|
        var base, e;
        base = PathName(t[\path]).fileName;
        e = ~files[base];
        if(e.notNil and: { e[\routine].notNil }) {
            e[\routine].stop;
            e[\routine] = nil;
        };

        // Ferma anche LFO azimuth
        t[\lfoSynth].notNil.if { t[\lfoSynth].free; t[\lfoSynth] = nil; t[\lfoActive] = false };
    };

    ~processing.sendMsg('/dj3d/deck/state', id.asString, 0);
};

// Momentary CUE: while on -> play from cue; on release -> stop and reset to cue
~deckCueHold = { |id, state|
    var d;
    d = ~decks[id]; if(d.isNil) { ^nil };
    if(state.asBoolean) {
        ~deckStartFrom.(id, d[\cuePosSam]);
    }{
        // stop and hard-reset to cue (silent)
        ~deckStop.(id);
        ~deckRetriggerAll.(id, d[\cuePosSam]); // re-arm at cue point (muted)
    };
    ~processing.sendMsg('/dj3d/deck/cue_hold', id.asString, state.asInteger);
};

// Seek/cue set helpers
~secToSam = { |tSec, buf| (tSec * (buf ? Buffer).sampleRate).asInteger };

// --- Helper robusto per sample rate del deck ---
~deckSampleRate = { |id|
    var d = ~decks[id];
    // 1) se il buffer delle cuffie è pronto, usa quello
    if(d.notNil and: { d[\cueBuf].notNil }) { ^d[\cueBuf].sampleRate };

    // 2) altrimenti cerca il primo stem che ha il buffer pronto
    ~deckCollectStems.(id).do { |t|
        if(t[\buf].notNil) {
            ^t[\buf].sampleRate;
        };
    };

    // 3) fallback sicuro
    44100
};


// --- Sostituisci queste funzioni con versioni che usano ~deckSampleRate ---

~deckSetCueSec = { |id, sec|
    var d = ~decks[id], sr;
    if(d.isNil) { ^nil };
    sr = ~deckSampleRate.(id);
    d[\cuePosSam] = (sec.clip(0, 1e9) * sr).asInteger;

    // Se fermo, arma silenzioso gli stems (muted) a quella posizione
    if(d[\playing].not) {
        ~deckRetriggerAll.(id, d[\cuePosSam]);
    };
    ~processing.sendMsg('/dj3d/deck/cue_pos', id.asString, sec);
};

~deckSeekSec = { |id, sec|
    var d = ~decks[id], sr, targetSam;
    if(d.isNil) { ^nil };
    sr = ~deckSampleRate.(id);
    targetSam = (sec.clip(0, 1e9) * sr).asInteger;
    d[\cuePosSam] = targetSam;

    if(d[\playing]) {
        ~deckStartFrom.(id, targetSam);
    }{
        ~deckRetriggerAll.(id, targetSam);
    };
    ~processing.sendMsg('/dj3d/deck/seek_ack', id.asString, sec);
};

~deckSetLoopInSec = { |id, sec|
    var d = ~decks[id], sr;
    if(d.isNil) { ^nil };
    sr = ~deckSampleRate.(id);
    d[\loopInSam] = (sec.clip(0, 1e9) * sr).asInteger;
    if(d[\loopOutSam] <= d[\loopInSam]) {
        d[\loopOutSam] = d[\loopInSam] + (sr * 0.5).asInteger; // default 0.5s
    };
    ~deckEnsureLoopRoutine.(id);
    ~processing.sendMsg('/dj3d/deck/loop_in', id.asString, sec);
};

~deckSetLoopOutSec = { |id, sec|
    var d = ~decks[id], sr;
    if(d.isNil) { ^nil };
    sr = ~deckSampleRate.(id);
    d[\loopOutSam] = (sec.clip(0, 1e9) * sr).asInteger;
    if(d[\loopOutSam] <= d[\loopInSam]) {
        d[\loopOutSam] = d[\loopInSam] + (sr * 0.5).asInteger;
    };
    ~deckEnsureLoopRoutine.(id);
    ~processing.sendMsg('/dj3d/deck/loop_out', id.asString, sec);
};

// Nota: puoi tenere inalterati gli OSCdef; ora richiamano funzioni robuste.

~deckSetLoopEnable = { |id, on|
    var d;
    d = ~decks[id];
    d[\loopEnabled] = on.asBoolean;
    ~deckEnsureLoopRoutine.(id);
    ~processing.sendMsg('/dj3d/deck/loop_enable', id.asString, d[\loopEnabled].asInteger);
};

// BPM / Rate control
~deckSetBPM = { |id, bpmTarget|
    var d;
    d = ~decks[id];
    d[\bpmRef] = ~deckComputeRefBPM.(id);
    d[\bpmTarget] = bpmTarget.asFloat.max(1e-3);
    d[\rate] = (d[\bpmTarget] / d[\bpmRef]).clip(0.25, 4.0);
    ~deckApplyRate.(id);
    ~deckEnsureLoopRoutine.(id); // update loop timing
    ~processing.sendMsg('/dj3d/deck/bpm', id.asString, d[\bpmTarget], d[\bpmRef], d[\rate]);
};

// ================== ORCHESTRATION (NO GUI) ==================
~startFromFolder = { |folder|
    Routine {
        s.sync;
        ~setupAmbiMaster.();
        s.sync;
        ~processing.sendMsg('/dj3d/ready', folder, ~tracks.size, ~order, ~numChannels);
    }.play(AppClock);
};

// ================== CONTROL VIA OSC ==================

// Phones out (hw out index, stereo)
OSCdef(\dj3d_phones_out, { |msg|
    var outIdx = msg[1].asInteger;
    "OSC: /dj3d/phones/out -> %".format(outIdx).postln;
    ~setPhonesOut.(outIdx);
}, '/dj3d/phones/out');

// Deck: carica file principale -> cuffie (preparato) + stems
OSCdef(\dj3d_deck_load_file, { |msg|
    var id = msg[1].asString.asSymbol; // 'A' o 'B'
    var path = msg[2].asString;
    "OSC: /dj3d/deck/load_file % -> %".format(id, path).postln;
    ~deckLoadFile.(id, path);
}, '/dj3d/deck/load_file');

// Deck stems play/stop

OSCdef(\dj3d_deck_stop, { |msg|
    var id = msg[1].asString.asSymbol;
    "OSC: /dj3d/deck/stop %".format(id).postln;
    ~deckStop.(id);
}, '/dj3d/deck/stop');

// Deck CUE (momentary) + set cue
OSCdef(\dj3d_deck_cue_hold, { |msg|
    var id = msg[1].asString.asSymbol;
    var st = msg[2].asInteger;
    "OSC: /dj3d/deck/cue_hold % -> %".format(id, st).postln;
    ~deckCueHold.(id, st);
}, '/dj3d/deck/cue_hold');

OSCdef(\dj3d_deck_set_cue, { |msg|
    var id = msg[1].asString.asSymbol;
    var sec = msg[2].asFloat;
    "OSC: /dj3d/deck/set_cue % -> %s".format(id, sec).postln;
    ~deckSetCueSec.(id, sec);
}, '/dj3d/deck/set_cue');

// Deck BPM / speed
OSCdef(\dj3d_deck_bpm, { |msg|
    var id = msg[1].asString.asSymbol;
    var bpm = msg[2].asFloat;
    "OSC: /dj3d/deck/bpm % -> %".format(id, bpm).postln;
    ~deckSetBPM.(id, bpm);
}, '/dj3d/deck/bpm');

// Deck loop in/out/enable (seconds)
OSCdef(\dj3d_deck_loop_in, { |msg|
    var id = msg[1].asString.asSymbol;
    var sec = msg[2].asFloat;
    "OSC: /dj3d/deck/loop_in % -> %s".format(id, sec).postln;
    ~deckSetLoopInSec.(id, sec);
}, '/dj3d/deck/loop_in');

OSCdef(\dj3d_deck_loop_out, { |msg|
    var id = msg[1].asString.asSymbol;
    var sec = msg[2].asFloat;
    "OSC: /dj3d/deck/loop_out % -> %s".format(id, sec).postln;
    ~deckSetLoopOutSec.(id, sec);
}, '/dj3d/deck/loop_out');

OSCdef(\dj3d_deck_loop_enable, { |msg|
    var id = msg[1].asString.asSymbol;
    var on = msg[2].asInteger;
    "OSC: /dj3d/deck/loop_enable % -> %".format(id, on).postln;
    ~deckSetLoopEnable.(id, on);
}, '/dj3d/deck/loop_enable');

// Deck CUE (headphones) controls
OSCdef(\dj3d_deck_cue_volume, { |msg|
    var id = msg[1].asString.asSymbol;
    var v = msg[2].asFloat;
    "OSC: /dj3d/deck/cue_volume % -> %".format(id, v).postln;
    ~deckCueVolume.(id, v);
}, '/dj3d/deck/cue_volume');

OSCdef(\dj3d_deck_cue_state, { |msg|
    var id = msg[1].asString.asSymbol;
    var state = msg[2].asInteger;
    "OSC: /dj3d/deck/cue_state % -> %".format(id, state).postln;
    if(state == 0) { ~deckCueStop.(id) } {
        var d = ~decks[id];
        if(d[\cueBuf].notNil) { ~deckCuePlay.(id, d[\cueBuf]) };
    };
}, '/dj3d/deck/cue_state');

// Crossfader
OSCdef(\dj3d_crossfader, { |msg|
    var x = msg[1].asFloat;
    "OSC: /dj3d/crossfader -> %".format(x).postln;
    ~setCrossfader.(x);
}, '/dj3d/crossfader');

// Compat global play/stop (non indispensabile coi deck)
OSCdef(\dj3d_play, { |msg|
    "OSC: /dj3d/play (global)".postln;
    ~startRun.();
}, '/dj3d/play');

OSCdef(\dj3d_stop, { |msg|
    "OSC: /dj3d/stop (global)".postln;
    ~stopRun.();
}, '/dj3d/stop');

// Extra utility invariati
OSCdef(\dj3d_random_az, { |msg|
    "OSC: /dj3d/random_az".postln;
    ~tracks.do { |t| if(t[\lfoActive].not and: { t[\isPerc].not }) { t[\setAz].(1.0.rand) } };
}, '/dj3d/random_az');

OSCdef(\dj3d_shuffle_lfo, { |msg|
    "OSC: /dj3d/shuffle_lfo".postln;
    ~tracks.do { |t|
        var ls = t[\lfoSynth];
        ls.notNil.if { ls.set(\rate, exprand(0.1, 4.0)) };
    };
}, '/dj3d_shuffle_lfo');

OSCdef(\dj3d_add_reverb, { |msg|
    "OSC: /dj3d/add_reverb".postln;
    ~ambiReverb.isNil.if { ~addMasterReverb.() } { ~processing.sendMsg('/dj3d/reverb', 1) };
}, '/dj3d/add_reverb');

OSCdef(\dj3d_switch_decoder, { |msg|
    var t = msg[1].asString.asSymbol;
    "OSC: /dj3d/switch_decoder -> % (class=%)".format(t, t.class).postln;
    ~switchDecoder.(t);
}, '/dj3d/switch_decoder');

OSCdef(\dj3d_record, { |msg|
    var state = msg[1].asInteger;
    var path = (msg.size > 2).if({ msg[2].asString }, { nil });
    "OSC: /dj3d/record -> %, path: %".format(state, path ? "<auto>").postln;
    ~toggleRecord.(state, path);
}, '/dj3d/record');

OSCdef(\dj3d_free_all, { |msg|
    "OSC: /dj3d/free_all".postln;
    // cue
    ['A','B'].do { |id| ~deckCueStop.(id) };
    // stems
    ~tracks.do { |t| t[\free].() };
    ~tracks.clear;
    // fx/master
    ~ambiReverb !? { ~ambiReverb.free; ~ambiReverb = nil };
    ~decoder !? { ~decoder.free; ~decoder = nil };
    ~ambiMasterBus !? { ~ambiMasterBus.free; ~ambiMasterBus = nil };
    ~processing.sendMsg('/dj3d/freed');
}, '/dj3d/free_all');

// Deck: volume 0..1
OSCdef(\dj3d_deck_volume, { |msg|
    var id = msg[1].asString.asSymbol;
    var v = msg[2].asFloat.clip(0, 1);
    var d = ~decks[id];
    if(d.notNil) {
        d[\volume] = v;
        ~applyDeckStemsAmps.();
        // opzionale: feedback a Processing
        ~processing.sendMsg('/dj3d/deck/volume', id.asString, v);
    };
    "OSC: /dj3d/deck/volume % -> %".format(id, v).postln;
}, '/dj3d/deck/volume');

// Deck: speed (rate) come numero — default 1.0
OSCdef(\dj3d_deck_speed, { |msg|
    var id = msg[1].asString.asSymbol;
    var rate = msg[2].asFloat.clip(0.25, 4.0);
    var d = ~decks[id];
    if(d.notNil) {
        d[\rate] = rate;
        ~deckApplyRate.(id);
        ~deckEnsureLoopRoutine.(id); // se c’è un loop attivo, aggiorna i tempi
        // opzionale: feedback a Processing
        ~processing.sendMsg('/dj3d/deck/rate', id.asString, d[\rate]);
    };
    "OSC: /dj3d/deck/speed % -> %".format(id, rate).postln;
}, '/dj3d/deck/speed');

// === Helpers: seek in secondi con retrigger coerente ===

// === CONTROL VIA OSC: aggiunte dedicate ===

// Imposta il CUE (solo aggiorna d[\cuePosSam], non muove il playhead)


// CUE momentary (hold): 1 = press -> parte dal CUE; 0 = release -> stop e ritorna al CUE
OSCdef(\dj3d_deck_cue_hold, { |msg|
    var id = msg[1].asString.asSymbol;
    var st = msg[2].asInteger;
    "OSC: /dj3d/deck/cue_hold % -> %".format(id, st).postln;
    ~deckCueHold.(id, st);
}, '/dj3d/deck/cue_hold');

// Play con parametro opzionale (secondi)
// /dj3d/deck/play A            -> vecchio comportamento (usa cuePosSam o loopIn)
// /dj3d/deck/play A 37.52      -> forza start da 37.52s (aggiorna cue interno)
OSCdef(\dj3d_deck_play, { |msg|
    var id = msg[1].asString.asSymbol;
    var d = ~decks[id];
    var hasPos = msg.size > 2;
    var sec, stems, sr, startSam;

    if(d.isNil) { "[SC][ERR] deck % non trovato".format(id).warn; ^nil };

    if(hasPos) {
        sec = msg[2].asFloat;
        stems = ~deckCollectStems.(id);
        // sampleRate sicuro
        sr = (stems.notEmpty and: { stems.first[\buf].notNil }).if({ stems.first[\buf].sampleRate }, { 44100 });
        startSam = (sec.clip(0, 1e9) * sr).asInteger;

        // Se loop attivo, forza la partenza dentro il loop
        if(d[\loopEnabled] and: { d[\loopOutSam] > d[\loopInSam] }) {
            if(startSam < d[\loopInSam] or: { startSam >= d[\loopOutSam] }) {
                startSam = d[\loopInSam];
                sec = d[\loopInSam] / sr;
            };
        };

        d[\cuePosSam] = startSam;
        "OSC: /dj3d/deck/play % (from %.3f s)".format(id, sec).postln;
        ~deckStartFrom.(id, startSam);
    }{
        "OSC: /dj3d/deck/play % (cue default)".format(id).postln;
        ~deckPlay.(id);
    };
}, '/dj3d/deck/play');

OSCdef(\dj3d_decoder_editor, { |msg|
    var on = msg[1].asInteger;
    "OSC: /dj3d/decoder/editor -> %".format(on).postln;

    if(~decoder.isNil) {
        "[SC] Decoder non inizializzato (chiama ~setupAmbiMaster)".warn;
        ^nil;
    };

    if(~decoder.respondsTo(\editor)) {
        ~decoder.editor(on.asBoolean);
    }{
        try {
            if(on == 1) { ~decoder.showEditor } { ~decoder.hideEditor };
        }{
            "[SC] VSTPluginController: no editor()/showEditor/hideEditor available.".warn;
        };
    };
}, '/dj3d/decoder/editor');

OSCdef(\dj3d_encoder_meter_fwd, { |msg|
    // SendTrig invia: ['/tr', nodeID, trigID, value]
    var nodeID = msg[1];
    var tid    = msg[2].asInteger;
    var amp    = msg[3].asFloat;

    // Decodifica: 0..99 => Deck A, 100..199 => Deck B
    var deck = (tid >= 100).if({ 'B' }, { 'A' });
    var idx  = tid % 100;

    ~processing.sendMsg('/dj3d/deck/encoder_level', deck.asString, idx, amp);
}, '/tr');

OSCdef(\dj3d_deck_encoder_editor, { |msg|
    var deck   = msg[1].asString.asSymbol;  // 'A' | 'B'
    var idx    = msg[2].asInteger;         // deck-local index
    var on     = msg[3].asInteger;

    var tracks = ~deckCollectStems.(deck);
    var tr = (idx >= 0 and: { idx < tracks.size }).if({ tracks[idx] }, { nil });

    "OSC: /dj3d/deck/encoder/editor % % -> %".format(deck, idx, on).postln;

    if(tr.isNil) { "[SC] Encoder track non trovata".warn; ^nil };

    if(tr[\encoder].notNil) {
        if(tr[\encoder].respondsTo(\editor)) {
            tr[\encoder].editor(on.asBoolean);
        }{
            try {
                (on == 1).if({ tr[\encoder].showEditor }, { tr[\encoder].hideEditor });
            }{
                "[SC] Encoder controller: no editor()/showEditor/hideEditor".warn;
            };
        };
    }{
        "[SC] Encoder non pronto per questo canale".warn;
    };
}, '/dj3d/deck/encoder/editor');

// ================== RICEZIONE ANALISI VIA OSC (da Python) ==================

// ================== OSC LISTENERS (analysis da Python) ==================

// /analysis/start n_files
OSCdef(\anaStart, { |msg|
    ~files.clear;
    ~expectedFiles = msg[1].asInteger;
    ~filesFinalizedCount = 0;
    ("[SC] /analysis/start | expected files = %".format(~expectedFiles)).postln;
}, '/analysis/start');

// /analysis/file_start name
OSCdef(\fileStart, { |msg|
    var name = msg[1].asString;
    ~ensureFileEntry.(name);
    ("[SC] /analysis/file_start | %".format(name)).postln;
}, '/analysis/file_start');

// /analysis/file_bpm name bpm
OSCdef(\fileBPM, { |msg|
    var name = msg[1].asString;
    var bpm  = msg[2].asFloat;
    ~ensureFileEntry.(name);
    ~files[name].put(\bpm, bpm);
    ("[SC] /analysis/file_bpm | % : %".format(name, bpm)).postln;
}, '/analysis/file_bpm');

// helper per chunk
~storeChunk = { |msg, keySym|
    var name = msg[1].asString;
    var idx  = msg[2].asInteger;
    var cnt  = msg[3].asInteger;
    var vals = msg.copyToEnd(4).keep(cnt);
    ~ensureFileEntry.(name);
    ~files[name][\chunks][keySym][idx] = vals;
    ("[SC] % | % | idx=% count=%"
        .format(msg[0], name, idx, cnt)).postln;
};

// chunk stream
OSCdef(\timesChunk, { |msg| ~storeChunk.(msg, \times)    }, '/analysis/onset_times_chunk');
OSCdef(\posChunk,   { |msg| ~storeChunk.(msg, \pos)      }, '/analysis/onset_pos_chunk');
OSCdef(\fluxChunk,  { |msg| ~storeChunk.(msg, \flux)     }, '/analysis/onset_strength_chunk');
OSCdef(\cntrChunk,  { |msg| ~storeChunk.(msg, \contrast) }, '/analysis/onset_contrast_chunk');

// /analysis/file_end name
OSCdef(\fileEnd, { |msg|
    var name = msg[1].asString;
    ("[SC] /analysis/file_end | %".format(name)).postln;
    ~finalizeFile.(name);
}, '/analysis/file_end');

// /analysis/global_bpm bpm
OSCdef(\globalBPM, { |msg|
    ~globalBPM = msg[1].asFloat;
    ("[SC] /analysis/global_bpm | %".format(~globalBPM)).postln;
}, '/analysis/global_bpm');

// /analysis/end
OSCdef(\anaEnd, { |msg|
    "[SC] /analysis/end".postln;
    ("[SC] Files received: % / expected: %"
        .format(~files.keys.size, ~expectedFiles)).postln;

    if((~expectedFiles > 0) and: { ~filesFinalizedCount >= ~expectedFiles }) {
        ("[SC] Analysis complete: %/% files finalized."
            .format(~filesFinalizedCount, ~expectedFiles)).postln;
        // opzionale: notifica a Processing
        ~processing.sendMsg('/analysis/ready', ~filesFinalizedCount);
    }{
        ("[SC] Analysis finished but %/% finalized."
            .format(~filesFinalizedCount, ~expectedFiles)).postln;
    };
}, '/analysis/end');












// Auto-setup master + decks (idle)
~setupAmbiMaster.();
~initDecks.();
~setCrossfader.(0.5);
"DJ3D headless + 2 Decks + Stems Loader ready — listening on port %, sending to %:%"
    .format(~scOscInPort, ~processingHost, ~processingPort).postln;
~processing.sendMsg('/dj3d/ready', "<idle>", 0, ~order, ~numChannels);

// USO (da Processing):
// /dj3d/phones/out 0|2|4...
// /dj3d/deck/load_file A /path/file.wav
// /dj3d/deck/set_cue A 0.0
// /dj3d/deck/loop_in A 4.0 ; /dj3d/deck/loop_out A 8.0 ; /dj3d/deck/loop_enable A 1
// /dj3d/deck/bpm A 124.0
// /dj3d/deck/cue_hold A 1 (press) ; /dj3d/deck/cue_hold A 0 (release)
// /dj3d/deck/play A ; /dj3d/deck/stop A
// /dj3d/crossfader 0..1
)
~decoder.controller.postln;
~decoder.info.postln;
~decoder.parameters.do{|p| p.postln };
s.meter;

