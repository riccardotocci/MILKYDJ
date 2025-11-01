// Analisi offline: BPM + beat grid + waveform reale (peak envelope)
// WAV/AIFF PCM supportati. Niente analisi di frequenze (nessuna FFT).

import javax.sound.sampled.*;
import java.util.Arrays;
import java.util.ArrayList;

interface AnalysisProgress {
  void onProgress(float p);
}

class TrackAnalysis {
  float sampleRate;
  float durationSec;
  float bpm;
  ArrayList<Float> beats = new ArrayList<Float>(); // secondi dal t0

  // Waveform peak envelope (min/max per frame) normalizzata [-1..1]
  float[] wfMin;
  float[] wfMax;
  float   wfHopSec; // ~0.01s

  int beatIndexAtTime(float t) {
    if (beats == null || beats.isEmpty()) return -1;
    int lo = 0, hi = beats.size() - 1, ans = -1;
    while (lo <= hi) {
      int mid = (lo + hi) >>> 1;
      float v = beats.get(mid);
      if (v <= t) { ans = mid; lo = mid + 1; }
      else { hi = mid - 1; }
    }
    return ans;
  }

  IntRange beatIndexRangeBetween(float t0, float t1) {
    if (beats == null || beats.isEmpty()) return null;
    int iStart = lowerBound(beats, t0);
    int iEnd = upperBound(beats, t1) - 1;
    if (iStart >= beats.size() || iEnd < 0 || iStart > iEnd) return null;
    IntRange p = new IntRange();
    p.i0 = max(0, iStart);
    p.i1 = min(beats.size()-1, iEnd);
    return p;
  }

  int lowerBound(ArrayList<Float> a, float v) {
    int lo = 0, hi = a.size();
    while (lo < hi) {
      int mid = (lo + hi) >>> 1;
      if (a.get(mid) < v) lo = mid + 1;
      else hi = mid;
    }
    return lo;
  }

  int upperBound(ArrayList<Float> a, float v) {
    int lo = 0, hi = a.size();
    while (lo < hi) {
      int mid = (lo + hi) >>> 1;
      if (a.get(mid) <= v) lo = mid + 1;
      else hi = mid;
    }
    return lo;
  }
}

class IntRange { int i0, i1; }

class BPMAnalyzer {

  TrackAnalysis analyzeFile(java.io.File file, AnalysisProgress progress) throws Exception {
    AudioInputStream ais = AudioSystem.getAudioInputStream(file);
    AudioFormat fmt = ais.getFormat();

    if (fmt.getEncoding() != AudioFormat.Encoding.PCM_SIGNED) {
      AudioFormat target = new AudioFormat(
        AudioFormat.Encoding.PCM_SIGNED,
        fmt.getSampleRate(),
        16,
        fmt.getChannels(),
        fmt.getChannels() * 2,
        fmt.getSampleRate(),
        fmt.isBigEndian()
      );
      ais = AudioSystem.getAudioInputStream(target, ais);
      fmt = target;
    }
    if (fmt.getSampleSizeInBits() != 16) {
      throw new RuntimeException("Formato non supportato (serve PCM 16-bit).");
    }

    float sr = fmt.getSampleRate();
    int ch = fmt.getChannels();
    boolean big = fmt.isBigEndian();

    byte[] raw = ais.readAllBytes();
    int totalSamples = raw.length / 2 / ch;
    float[] mono = new float[totalSamples];

    int idx = 0;
    int frameCount = totalSamples;
    int bIdx = 0;
    float absPeak = 0;
    for (int i = 0; i < frameCount; i++) {
      float sum = 0;
      for (int c = 0; c < ch; c++) {
        int b1 = raw[bIdx++] & 0xff;
        int b2 = raw[bIdx++] & 0xff;
        int val = big ? ((b1 << 8) | b2) : ((b2 << 8) | b1);
        if (val > 32767) val -= 65536;
        float s = (val / 32768.0f);
        sum += s;
      }
      float m = sum / ch;
      mono[idx++] = m;
      float a = abs(m);
      if (a > absPeak) absPeak = a;

      if (progress != null && i % 500000 == 0) {
        progress.onProgress((float)i / (float)frameCount);
      }
    }
    float durationSec = mono.length / sr;

    float norm = (absPeak > 1e-9f) ? (1.0f / absPeak) : 1.0f;
    if (abs(norm - 1.0f) > 1e-6f) {
      for (int i = 0; i < mono.length; i++) mono[i] *= norm;
    }

    int win = 1024;
    int hop = 512;
    int frames = (mono.length >= win) ? (1 + (mono.length - win) / hop) : 0;
    frames = max(0, frames);
    float hopSec = hop / sr;

    float[] energy = new float[frames];
    float[] flux = new float[frames];

    float prevE = 0;
    for (int f = 0; f < frames; f++) {
      int start = f * hop;
      double e = 0;
      for (int n = 0; n < win; n++) {
        float s = mono[start + n];
        e += s * s;
      }
      energy[f] = (float)e;
      float d = energy[f] - prevE;
      flux[f] = max(0, d);
      prevE = energy[f];
    }

    smoothInPlace(flux, 5);

    float meanV = mean(flux);
    float std = stddev(flux, meanV);
    float th = meanV + std * 0.6f;

    ArrayList<Integer> onsetFrames = new ArrayList<Integer>();
    for (int f = 1; f < frames-1; f++) {
      if (flux[f] > th && flux[f] > flux[f-1] && flux[f] >= flux[f+1]) {
        onsetFrames.add(f);
      }
    }

    float minBPM = 60, maxBPM = 200;
    int minLag = round((60.0f / maxBPM) * (sr / hop));
    int maxLag = round((60.0f / minBPM) * (sr / hop));
    minLag = max(1, minLag);
    maxLag = max(minLag+1, maxLag);

    int bestLag = minLag;
    double bestScore = -1;
    for (int lag = minLag; lag <= maxLag; lag++) {
      double acc = 0;
      for (int f = lag; f < frames; f++) {
        acc += flux[f] * flux[f - lag];
      }
      if (acc > bestScore) {
        bestScore = acc;
        bestLag = lag;
      }
    }

    float periodSec = bestLag * hopSec;
    float bpm = 60.0f / max(1e-6f, periodSec);

    float t0 = 0;
    if (!onsetFrames.isEmpty()) {
      t0 = onsetFrames.get(0) * hopSec;
      float bestOff = 0;
      int votesBest = -1;
      for (int step = -8; step <= 8; step++) {
        float off = step * (periodSec / 16f);
        int votes = 0;
        for (int of : onsetFrames) {
          float tt = of * hopSec;
          float ph = (tt - (t0 + off)) / periodSec;
          float dist = abs(ph - round(ph));
          if (dist < 0.1) votes++;
        }
        if (votes > votesBest) { votesBest = votes; bestOff = off; }
      }
      t0 += bestOff;
      if (t0 < 0) t0 = 0;
    }

    ArrayList<Float> beats = new ArrayList<Float>();
    float t = t0;
    while (t <= durationSec) {
      beats.add(t);
      t += periodSec;
    }
    if (beats.size() < 4) {
      beats.clear();
      for (t = 0; t <= durationSec; t += periodSec) beats.add(t);
    }

    int envWin = max(1, round(sr * 0.010f));   // ~10 ms
    int envBins = (mono.length + envWin - 1) / envWin;
    float[] wfMin = new float[envBins];
    float[] wfMax = new float[envBins];
    for (int b = 0; b < envBins; b++) {
      int start = b * envWin;
      int end = min(mono.length, start + envWin);
      float mn = +1e9f, mx = -1e9f;
      for (int i = start; i < end; i++) {
        float v = mono[i];
        if (v < mn) mn = v;
        if (v > mx) mx = v;
      }
      if (start >= mono.length) { mn = 0; mx = 0; }
      wfMin[b] = (mn == +1e9f) ? 0 : mn;
      wfMax[b] = (mx == -1e9f) ? 0 : mx;
    }
    float wfHopSec = envWin / sr;

    TrackAnalysis a = new TrackAnalysis();
    a.sampleRate = sr;
    a.durationSec = durationSec;
    a.bpm = bpm;
    a.beats = beats;
    a.wfMin = wfMin;
    a.wfMax = wfMax;
    a.wfHopSec = wfHopSec;

    return a;
  }

  void smoothInPlace(float[] x, int radius) {
    if (x.length == 0) return;
    float[] y = new float[x.length];
    int n = x.length;
    for (int i = 0; i < n; i++) {
      int i0 = max(0, i - radius);
      int i1 = min(n-1, i + radius);
      float s = 0;
      int c = 0;
      for (int k = i0; k <= i1; k++) { s += x[k]; c++; }
      y[i] = s / max(1, c);
    }
    System.arraycopy(y, 0, x, 0, n);
  }

  float mean(float[] x) {
    double s = 0; for (float v: x) s += v; return (float)(s / max(1, x.length));
  }

  float stddev(float[] x, float m) {
    double s = 0; for (float v: x) { double d=v-m; s += d*d; }
    return (float)Math.sqrt(s / max(1, x.length));
  }
}
