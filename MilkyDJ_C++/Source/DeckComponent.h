#pragma once
#include <JuceHeader.h>
#include "AudioEngine.h"
#include "TrackDecoder.h"
#include "VUMeter.h"
#include "DJLookAndFeel.h"
#include "BpmAnalyzer.h"

class DeckComponent : public juce::Component,
                      private juce::Timer
{
public:
    DeckComponent(const juce::String& title, Deck& deck, juce::AudioFormatManager& fm);
    ~DeckComponent() override;

    void paint(juce::Graphics&) override;
    void resized() override;

    void loadFile(const juce::File& file);
    void setSyncTarget(DeckComponent* target) { syncTarget = target; }

    void togglePlay();
    void setPlaying(bool shouldPlay);
    void pressCue();
    void releaseCue();
    void sync();
    void setLoopIn();
    void setLoopOut();
    void toggleLoop();
    void resizeLoop(double factor);
    void setBeatLoop(double beats, bool active);
    void jogBySeconds(double seconds);
    void seekToStart(bool startPlaying);
    void setPitchNormalized(float value);
    void triggerHotCue(int index);
    void clearHotCue(int index);
    void toggleStem(int index);
    void toggleEffect(int index);

    bool getPlaying() const { return isPlaying; }
    bool getCueHeld() const { return cueHeld; }
    bool getLoopEnabled() const { return loopEnabled; }
    bool getStemEnabled(int index) const;
    bool getEffectEnabled(int index) const;
    bool hasHotCue(int index) const;

    // Accessors per waveform globale
    juce::AudioThumbnail& getThumbnail() { return thumbnail; }
    const juce::AudioThumbnail& getThumbnail() const { return thumbnail; }
    int64_t getTrackTotalSamples() const { return trackTotalSamples; }
    double getPlaybackSeconds() const { return deckRef.getPlaybackSamples() / deckRef.getModelSampleRate(); }

    // Beat/BPM reali
    const std::vector<double>& getBeatTimes() const { return beatTimes; }
    double getBpm() const { return bpm; }
    bool isAnalysisDone() const { return analysisDone; }

private:
    void timerCallback() override;
    void loadTrack();
    void doLoadFile(const juce::File& file);
    void updateStatus();

    void startAnalysis(const juce::File& file);
    void finishAnalysis(const juce::File& file, BpmAnalysisResult result);

    void mouseDown(const juce::MouseEvent& e) override;
    void mouseUp(const juce::MouseEvent& e) override;

    void performLoopIfNeeded();
    void syncToTarget();
    void seekWithBuffering(int64_t targetSamples, bool resumeAfterBuffering);
    int64_t getPhaseAlignedSample(const DeckComponent& target) const;
    void drawMiniWaveform(juce::Graphics& g, juce::Rectangle<int> area);

    DJLookAndFeel lnf;

    juce::String deckTitle;
    Deck& deckRef;
    juce::AudioFormatManager& formatManager;

    juce::TextButton loadButton { "Load" };
    juce::TextButton playPauseButton { "PLAY" };
    juce::TextButton cueButton { "Cue" };
    juce::TextButton syncButton { "Sync" };

    juce::TextButton loopInButton { "IN" };
    juce::TextButton loopOutButton { "OUT" };
    juce::TextButton loopNudgeLeft { "<" };
    juce::TextButton loopNudgeRight { ">" };
    juce::ToggleButton loopEnableButton { "Loop" };

    juce::Slider stemSliders[4];
    juce::TextButton stemButtons[4];
    const char* stemNames[4] { "Drums", "Bass", "Others", "Vocals" };

    juce::Slider effectSliders[4];
    juce::Label effectLabels[4];
    juce::Label effectGroupLabels[2];

    juce::Slider pitchSlider;
    juce::Label  pitchLabel { "Pitch", "Pitch" };

    VUMeter vuMeter;

    juce::AudioThumbnailCache thumbCache { 4 };
    juce::AudioThumbnail thumbnail { 512, formatManager, thumbCache };
    int64_t trackTotalSamples { 0 };

    std::unique_ptr<TrackDecoder> decoder;
    std::unique_ptr<BpmAnalysisThread> analysisThread;
    std::unique_ptr<juce::FileChooser> fileChooser;
    juce::File loadedFile;
    bool bufferingReady { false };
    bool resumeWhenBuffered { false };
    bool isPlaying { false };
    bool cueHeld { false };
    bool hasCue { false };
    int64_t cuePoint { 0 };
    std::array<int64_t, 4> hotCuePoints {};
    std::array<bool, 4> hotCueSet {};

    bool loopInSet { false };
    bool loopOutSet { false };
    bool loopEnabled { false };
    int64_t loopInSamples { 0 };
    int64_t loopOutSamples { 0 };
    double nudgeMillis { 200.0 };
    const int minLoopSamples = 2048;

    int readyThresholdSamples { 0 };

    // Beat analysis
    bool analysisDone { false };
    bool analysisInProgress { false };
    double bpm { 0.0 };
    std::vector<double> beatTimes;
    DeckComponent* syncTarget { nullptr };

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(DeckComponent)
};