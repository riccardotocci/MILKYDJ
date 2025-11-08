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
Server.default.options.outDevice_("Cuffie esterne");
(
// ================== SETTINGS ==================
~order = 3;
~numChannels = ((~order + 1) ** 2).asInteger;   // 3rd order -> 16 channels
~pluginNames = (
    encoder: "StereoEncoder",
    binauralDecoder: "BinauralDecoder",
    simpleDecoder: "SimpleDecoder",
    reverb:  "FdnReverb"
);

// IEM StereoEncoder params: azimuth=6, elevation=7
~encoderAzParam = 6;
~encoderElParam = 7;

// Decoder selection: 'binaural' or 'simple'
~decoderType = 'binaural';

// === Processing / OSC peer ===
~processingHost = "127.0.0.1";
~processingPort = 57121;          // Porta di Processing
~processing     = NetAddr(~processingHost, ~processingPort);

// Porta OSC di SC (default 57120)
~scOscInPort = NetAddr.langPort;

// Uscite cuffie (hw out index). Se usi interfacce multi-out, imposta p.es. 2 per usare out 2-3
~phonesOut = 0;  // canale di partenza (stereo -> out, out+1)

// Cartella di default (non usata nel nuovo load, lasciata per compatibilità)
~defaultFolder = "";

// ================== GLOBALS ==================
~ambiMasterBus = nil;
~ambiMasterGroup = nil;
~ambiMasterFXGroup = nil;
~decoder = nil;        // VSTPluginController
~ambiReverb = nil;

~tracks = List.new;    // lista di tracce (Event) caricate (stems)
~recorder = nil;
~recording = false;

// analisi da JSON: name(basename) -> entry (bpm, arrays...)
~files = Dictionary.new;
~expectedFiles = 0;
~filesFinalizedCount = 0;
~globalBPM = nil;

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

// basename -> track
~trackByBaseName = { |base|
    ~tracks.detect { |x| PathName(x[\path]).fileName == base }
};

// assicura un entry analisi
~ensureFileEntry = { |name|
    if(~files[name].isNil) {
        ~files[name] = (
            bpm: nil,
            onsetTimes: #[],
            onsetPos: #[],
            onsetFlux: #[],
            onsetContrast: #[],
            timeline: #[],
            routine: nil,
            finalized: false
        );
    };
};

// Stable percussion detection via filename
~isPercussionTrack = { |path|
    var filename = PathName(path).fileName.asString;
    var lower = filename.toLower;
    (lower.contains("drum") or: { lower.contains("kick") } or: { lower.contains("perc") } or: { lower.contains("bd") })
};

// JSON helpers (no direct reference to JSON class names)
~jsonFindClass = {
    var names, cls;
    names = ["JSON", "JSONlib", "SimpleJSON", "SCJson", "WispJSON"];
    cls = names.collect { |n| n.asSymbol.asClass }.detect(_.notNil);
    cls
};

~jsonParseText = { |text|
    var cls, sel, candidates, parsed, inst, tried;
    parsed = nil;

    cls = ~jsonFindClass.();
    if(cls.isNil) {
        "[SC][ERR] Nessuna classe JSON trovata (installa un quark JSON e ricompila).".warn;
        ~processing.sendMsg('/dj3d/error', "json_quark_missing");
        ^nil;
    };

    // 1) prova metodi di classe
    candidates = [\parse, \fromString, \read, \newFromString];
    sel = candidates.detect { |s| cls.respondsTo(s) };
    if(sel.notNil) {
        tried = sel;
        ^{
            parsed = cls.perform(sel, text);
        }.try({ |err|
            "[SC][ERR] JSON class method % fallito: %".format(tried, err).warn;
            parsed = nil;
        });
    };
    if(parsed.notNil) { ^parsed };

    // 2) prova metodi di istanza
    inst = ({
        cls.new
    }.try({ nil }));
    if(inst.notNil) {
        candidates = [\parse, \fromString, \read];
        sel = candidates.detect { |s| inst.respondsTo(s) };
        if(sel.notNil) {
            tried = sel;
            ^{
                parsed = inst.perform(sel, text);
            }.try({ |err|
                "[SC][ERR] JSON instance method % fallito: %".format(tried, err).warn;
                parsed = nil;
            });
        };
    };
    if(parsed.notNil) { ^parsed };

    "[SC][ERR] Nessun selettore compatibile trovato nella classe JSON: %".format(cls.asString).warn;
    ~processing.sendMsg('/dj3d/error', "json_no_compatible_api");
    nil
};

// trova JSON di analisi dentro la cartella stems: preferenze: <basename>.json, analysis.json, features.json, oppure primo .json
~findAnalysisJson = { |stemsDir, basenameNoExt|
    var candidates, found, js, pn;
    if(File.exists(stemsDir).not) { ^nil };

    candidates = [
        stemsDir +/+ (basenameNoExt ++ ".json"),
        stemsDir +/+ "analysis.json",
        stemsDir +/+ "features.json"
    ];

    found = candidates.detect { |p| File.exists(p) };
    if(found.notNil) { ^found };

    pn = PathName(stemsDir);
    js = pn.files.select { |f| f.extension.asString.toLower == "json" };
    if(js.notEmpty) { ^js.first.fullPath };

    nil
};

// ================== SYNTHDEFS ==================
SynthDef(\binauralDecoder, { | bus, out = 0 |
    var n = ~numChannels;
    Out.ar(out, VSTPlugin.ar(In.ar(bus, n), 2));
}).add;

SynthDef(\simpleDecoder, { | bus, out = 0 |
    var n = ~numChannels;
    Out.ar(out, VSTPlugin.ar(In.ar(bus, n), 2));
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

// ================== SERVER BOOT ==================
s.waitForBoot({
    "Server booted. Scanning plugins…".postln;
    VSTPlugin.search(verbose: false);

    // Verifica JSON senza nominare classi inesistenti
    if(~jsonFindClass.().isNil) {
        "[WARN] Nessuna classe JSON rilevata. Installa un quark JSON (es. 'JSON' o 'jsonlib') e poi Language > Recompile."
        .warn;
        ~processing.sendMsg('/dj3d/warn', "json_quark_missing");
    };

    ~processing.sendMsg('/dj3d/hello', ~scOscInPort, ~order, ~numChannels);
});

// ================== MASTER AMBISONIC ==================
~setupAmbiMaster = {
    var synthName, pluginName;

    ~ambiMasterBus !? { ~ambiMasterBus.free };
    ~ambiMasterBus = Bus.audio(s, ~numChannels);
    ~ambiMasterGroup = Group.head(s);
    ~decoder !? { ~decoder.free };

    synthName = (~decoderType == 'simple').if({ \simpleDecoder }, { \binauralDecoder });
    pluginName = (~decoderType == 'simple').if({ ~pluginNames[\simpleDecoder] }, { ~pluginNames[\binauralDecoder] });

    ~decoder = VSTPluginController(
        Synth(synthName, [\bus, ~ambiMasterBus, \out, 0],
            target: ~ambiMasterGroup, addAction: \addToTail)
    ).open(pluginName);

    ~ambiMasterFXGroup = Group.before(~decoder.synth);
    "Ambisonic master ready: %ch | Decoder: %".format(~numChannels, pluginName).postln;
    ~processing.sendMsg('/dj3d/decoder', (~decoderType == 'simple').if({ "simple" }, { "binaural" }));
};

~switchDecoder = { |newType|
    var wasPlaying = ~isPlaying;
    if(wasPlaying) { ~stopRun.() };
    ~decoderType = newType;
    ~setupAmbiMaster.();
    ("[SC] Switched to % decoder".format(
        (~decoderType == 'simple').if({ "SimpleDecoder" }, { "BinauralDecoder" })
    )).postln;
    ~processing.sendMsg('/dj3d/decoder', (~decoderType == 'simple').if({ "simple" }, { "binaural" }));
    if(wasPlaying) { ~startRun.() };
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
~makeTrack = { |path, idx, deckId=nil|
    var file, buf, ambiBus, grp, lfoBus, tr, numCh, elBus, elSmoothSynth, isPerc, synthName;

    file = SoundFile.openRead(path);
    numCh = file.numChannels;

    if ((numCh != 1) and: (numCh != 2)) {
        ("[WARN] % is %ch, expected mono or stereo; skipping."
            .format(PathName(path).fileName, numCh)).warn;
        file.close; ^nil;
    };
    file.close;

    ambiBus = Bus.audio(s, ~numChannels);
    grp = Group.before(~ambiMasterGroup);
    lfoBus = Bus.control(s, 1);

    isPerc = ~isPercussionTrack.(path);
    ("[SC] Track: % | isPerc: % | deck: %".format(PathName(path).fileName, isPerc, deckId)).postln;

    elBus = Bus.control(s, 1);
    elSmoothSynth = Synth.tail(grp, \elevSmoother, [
        \outBus, elBus,
        \targetDeg, (isPerc).if({ 0 }, { 90 }),
        \lag, 0.15
    ]);

    tr = ();
    tr[\index] = idx;
    tr[\path] = path;
    tr[\buf] = nil;
    tr[\group] = grp;
    tr[\ambiBus] = ambiBus;
    tr[\player] = nil;
    tr[\encoder] = nil;
    tr[\lfoBus] = lfoBus;
    tr[\lfoSynth] = nil;
    tr[\lfoActive] = false;
    tr[\numCh] = numCh;
    tr[\elBus] = elBus;
    tr[\elSmooth] = elSmoothSynth;
    tr[\isPerc] = isPerc;
    tr[\deck] = deckId;   // assegnazione al deck

    tr[\setAz] = { |x|
        tr[\encoder].notNil.if {
            if(tr[\isPerc]) { tr[\encoder].set(~encoderAzParam, 0.5) } {
                tr[\encoder].set(~encoderAzParam, x)
            };
        };
    };

    tr[\mapAzToLfo] = {
        if(tr[\isPerc]) {
            ("[SC] Percussion track, skipping Az LFO mapping for: %"
                .format(PathName(tr[\path]).fileName)).postln;
        }{
            tr[\encoder].notNil.if { tr[\encoder].map(~encoderAzParam, tr[\lfoBus]) };
        };
    };

    tr[\unmapAz] = { tr[\encoder].notNil.if { tr[\encoder].unmap(~encoderAzParam) } };
    tr[\setLfoSynth] = { |synth| tr[\lfoSynth] = synth };
    tr[\free] = {
        tr[\lfoSynth].notNil.if { tr[\lfoSynth].free };
        tr[\elSmooth].notNil.if { tr[\elSmooth].free };
        tr[\buf].notNil.if { tr[\buf].free };
        tr[\ambiBus].free;
        tr[\group].free;
    };

    buf = Buffer.readChannel(s, path,
        channels: (numCh == 1).if { [0] } { [0, 1] },
        action: { |b|
            {
                synthName = (numCh == 1).if { \monoPlayer } { \stereoPlayer };
                tr[\buf] = b;

                tr[\player] = Synth.head(grp, synthName, [
                    \out, ambiBus, \buf, b, \rate, 1, \amp, 0, \trig, 0, \startPos, 0
                ]);

                tr[\encoder] = VSTPluginController(
                    Synth.tail(grp, \stereoEncoder, [\bus, ambiBus])
                ).open(~pluginNames[\encoder], action: { |self|
                    self.set(~encoderAzParam, (tr[\isPerc]).if({ 0.5 }, { 1.0.rand }));
                    if(tr[\isPerc]) {
                        self.set(~encoderElParam, 0.5);
                    }{
                        self.map(~encoderElParam, elBus);
                    };
                });
                Synth.tail(grp, \ambiThrow, [\from, ambiBus, \to, ~ambiMasterBus]);

                ~processing.sendMsg('/dj3d/track_loaded',
                    tr[\index], PathName(tr[\path]).fileName, tr[\numCh], tr[\isPerc].asInteger, (deckId ?? "-").asString);
            }.defer;
        }
    );

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
    if(~filesFinalizedCount <= 0) {
        "[SC] Nessuna analisi caricata. Carica un JSON prima di avviare.".warn;
        ~processing.sendMsg('/dj3d/run_denied', "no_analysis_loaded");
        ^nil;
    };

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

// ================== ANALYSIS: LOAD FROM JSON ==================
~loadAnalysisFromJSON = { |jsonPath|
    var jsonStr, data, filesArr, matched = 0, total = 0;

    if(jsonPath.isNil or: { jsonPath.asString.isEmpty }) {
        "[SC][ERR] JSON path non valido".warn;
        ~processing.sendMsg('/dj3d/error', "json_path_invalid"); ^nil;
    };

    if(File.exists(jsonPath).not) {
        "[SC][ERR] JSON non trovato: %".format(jsonPath).warn;
        ~processing.sendMsg('/dj3d/error', "json_not_found", jsonPath); ^nil;
    };

    if(~jsonFindClass.().isNil) {
        "[SC][ERR] Quark JSON mancante: impossibile fare il parse. Installa un quark JSON e ricompila."
        .warn;
        ~processing.sendMsg('/dj3d/error', "json_quark_missing");
        ^nil;
    };

    jsonStr = File.readAllString(jsonPath);

    data = ~jsonParseText.(jsonStr);
    if(data.isNil) {
        // error già notificato
        ^nil;
    };

    // reset (ma NON liberiamo le tracce: il JSON si riferisce alle stems correnti)
    ~files.clear;
    ~filesFinalizedCount = 0;

    ~globalBPM = (data[\global_bpm] ?? data["global_bpm"]).asFloat;
    (~globalBPM.notNil).if { ~processing.sendMsg('/dj3d/global_bpm', ~globalBPM) };

    filesArr = data[\files] ?? data["files"];
    if(filesArr.isNil or: { filesArr.isArray.not }) {
        "[SC][ERR] JSON: campo 'files' mancante o non array".warn;
        ~processing.sendMsg('/dj3d/error', "json_schema_invalid"); ^nil;
    };

    total = filesArr.size;
    filesArr.do { |entry|
        var name, base, times, pos, flux, cntr, bpm, n;
        name = (entry[\name] ?? entry["name"]).asString;
        base = PathName(name).fileName; // normalizza a basename
        times = (entry[\onset_times] ?? entry["onset_times"] ?? entry[\times] ?? entry["times"]) ? #[];
        pos   = (entry[\onset_pos]   ?? entry["onset_pos"]   ?? entry[\pos]   ?? entry["pos"])   ? #[];
        flux  = (entry[\onset_flux]  ?? entry["onset_flux"]  ?? entry[\flux]  ?? entry["flux"])  ? #[];
        cntr  = (entry[\onset_contrast] ?? entry["onset_contrast"] ?? entry[\contrast] ?? entry["contrast"]) ? #[];
        bpm   = (entry[\bpm] ?? entry["bpm"]).asFloat;

        if(~trackByBaseName.(base).notNil) {
            n = [times.size, pos.size, flux.size, cntr.size].minItem;
            if(n <= 0) {
                ("[SC][WARN] Timeline vuota per %".format(base)).postln;
            }{
                ~ensureFileEntry.(base);
                ~files[base].putAll((
                    bpm: bpm,
                    onsetTimes: times.copyRange(0, n-1),
                    onsetPos: pos.copyRange(0, n-1),
                    onsetFlux: flux.copyRange(0, n-1),
                    onsetContrast: cntr.copyRange(0, n-1),
                    timeline: Array.fill(n, { |i|
                        ( time: times[i], beat: pos[i], flux: flux[i], contrast: cntr[i] )
                    }),
                    finalized: true
                ));
                matched = matched + 1;
                ~filesFinalizedCount = ~filesFinalizedCount + 1;
                ~processing.sendMsg('/dj3d/file_finalized', base, n, bpm ?? -1);
            };
        }{
            ("[SC][INFO] Analisi per % ignorata: stem non caricato".format(base)).postln;
        };
    };

    ~expectedFiles = matched;
    ("[SC] Analisi JSON caricata. Matched % / total %".format(matched, total)).postln;

    if(matched > 0) {
        ~processing.sendMsg('/dj3d/analysis_loaded', jsonPath, matched, total);
        ~processing.sendMsg('/dj3d/play_enabled', 1, ~filesFinalizedCount, ~expectedFiles);
    }{
        ~processing.sendMsg('/dj3d/analysis_loaded', jsonPath, matched, total);
        ~processing.sendMsg('/dj3d/play_enabled', 0, 0, 0);
    };
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
    var toRemove, d, base, e;
    toRemove = ~tracks.select { |t| t[\deck] == id };
    // stop looping routine
    d = ~decks[id];
    d[\loopRoutine].notNil.if { d[\loopRoutine].stop; d[\loopRoutine] = nil };
    toRemove.do { |t|
        // stop routine automazioni se presente
        base = PathName(t[\path]).fileName;
        e = ~files[base];
        e.notNil.if { e[\routine].notNil.if { e[\routine].stop; e[\routine] = nil } };
        t[\free].();
        ~tracks.remove(t);
    };
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

// Carica stems+json per un deck dato un "file" principale; NON avvia più il CUE
~deckLoadFile = { |id, filePath|
    var d, p, parentDir, baseNoExt, stemsDir, newStems, jsonPath, minFrames;

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

    // 3) ANALYSIS JSON: dentro la cartella stems
    jsonPath = ~findAnalysisJson.(stemsDir, baseNoExt);
    if(jsonPath.notNil) {
        ~loadAnalysisFromJSON.(jsonPath);
    }{
        "[SC][WARN] JSON analisi non trovato in: %".format(stemsDir).postln;
        ~processing.sendMsg('/dj3d/warn', "json_not_found_in_stems", stemsDir);
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

// Play/Pause deck (stems)
~deckPlay = { |id|
    var d, startSam;
    d = ~decks[id]; if(d.isNil) { ^("[SC][ERR] Deck % non esiste".format(id)).warn };
    // start from cue or loopIn if loop enabled
    startSam = (d[\loopEnabled]).if({ d[\loopInSam] }, { d[\cuePosSam] });
    ~deckStartFrom.(id, startSam);
};

~deckStop = { |id|
    var d;
    d = ~decks[id]; if(d.isNil) { ^("[SC][ERR] Deck % non esiste".format(id)).warn };
    d[\playing] = false;
    d[\loopRoutine].notNil.if { d[\loopRoutine].stop; d[\loopRoutine] = nil };
    ~applyDeckStemsAmps.();
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
~deckSampleRate = { |id| var d,t;
    d = ~decks[id];
    // 1) se il buffer delle cuffie è pronto, usa quello
    if(d.notNil and: { d[\cueBuf].notNil }) { ^d[\cueBuf].sampleRate };

    // 2) altrimenti cerca il primo stem che ha il buffer pronto
    t = ~deckCollectStems.(id).detect { |tr| tr[\buf].notNil };
    if(t.notNil) { ^t[\buf].sampleRate };

    // 3) fallback sicuro
    44100
};

// --- Sostituisci queste funzioni con versioni che usano ~deckSampleRate ---

~deckSetCueSec = { |id, sec|
    var d = ~decks[id], sr;
    if(d.isNil) { ^nil };
    sr = ~deckSampleRate.(id);
    d[\cuePosSam] = (sec.clip(0, 1e9) * sr).asInteger;

    // Se è fermo, arma silenzioso per allineare gli stems
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

// Deck: carica file principale -> cuffie (preparato) + stems + json
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

// Analisi JSON manuale (se necessario)
OSCdef(\dj3d_load_analysis, { |msg|
    var jsonPath = msg[1].asString;
    "OSC: /dj3d/load_analysis -> %".format(jsonPath).postln;
    ~loadAnalysisFromJSON.(jsonPath);
}, '/dj3d/load_analysis');

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
    var t = msg[1].asString;
    "OSC: /dj3d/switch_decoder -> %".format(t).postln;
    if(t == "simple" or: { t == "binaural" }) { ~switchDecoder.(t) } { "[SC] Unknown decoder type".warn };
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
~deckSeekSec = { |id, sec|
    var d, stems, sr, targetSam;
    d = ~decks[id]; if(d.isNil) { ^nil };
    stems = ~deckCollectStems.(id);
    sr = stems.first.notNil.if({ stems.first[\buf].sampleRate }, { 44100 });
    targetSam = (sec.clip(0, 1e9) * sr).asInteger;

    // aggiorna il cue del deck (lo riutilizziamo anche altrove)
    d[\cuePosSam] = targetSam;

    if(d[\playing]) {
        // se sta suonando: riparti subito da targetSam
        ~deckStartFrom.(id, targetSam);
    }{
        // se è fermo: riallinea gli stems a targetSam (muted) così sono “armati”
        ~deckRetriggerAll.(id, targetSam);
    };

    ~processing.sendMsg('/dj3d/deck/seek_ack', id.asString, sec);
};

// === CONTROL VIA OSC: aggiunte dedicate ===

// Imposta il CUE (solo aggiorna d[\cuePosSam], non muove il playhead)
OSCdef(\dj3d_deck_set_cue, { |msg|
    var id = msg[1].asString.asSymbol;
    var sec = msg[2].asFloat;
    var d = ~decks[id];
    var stems = ~deckCollectStems.(id);
    var sr = stems.first.notNil.if({ stems.first[\buf].sampleRate }, { 44100 });
    if(d.notNil) {
        d[\cuePosSam] = (sec.clip(0, 1e9) * sr).asInteger;
        ~processing.sendMsg('/dj3d/deck/cue_pos', id.asString, sec);
    };
    "OSC: /dj3d/deck/set_cue % -> %s".format(id, sec).postln;
}, '/dj3d/deck/set_cue'); // se già c'è, puoi tenere l’OSCdef esistente

// Seek “attivo”: sposta playhead alla posizione (se playing) o arma silenzioso (se fermo)
OSCdef(\dj3d_deck_seek, { |msg|
    var id = msg[1].asString.asSymbol;
    var sec = msg[2].asFloat;
    "OSC: /dj3d/deck/seek % -> %s".format(id, sec).postln;
    ~deckSeekSec.(id, sec);
}, '/dj3d/deck/seek');

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

// Auto-setup master + decks (idle)
~setupAmbiMaster.();
~initDecks.();
~setCrossfader.(0.5);
"DJ3D headless + JSON + 2 Decks + Stems Loader ready — listening on port %, sending to %:%"
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