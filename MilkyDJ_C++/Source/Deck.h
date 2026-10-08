#pragma once
#include <array>
#include <atomic>
#include <memory>
#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_dsp/juce_dsp.h>
#include "AmbisonicStemEncoder.h"
#include "LookaheadBuffer.h"
#include "SeparationWorker.h"

class Deck
{
public:
    Deck();
    ~Deck();

    void setModelFile(const juce::File& f);
    void setStemGain(int stemIdx, float g);
    void setStemEnabled(int stemIdx, bool enabled)
    {
        if (stemIdx >= 0 && stemIdx < static_cast<int>(stemEnabled.size()))
            stemEnabled[static_cast<size_t>(stemIdx)].store(enabled);
    }
    void setLowEqDb(float db)  { lowEqDb.store(juce::jlimit(-24.0f, 12.0f, db)); }
    void setMidEqDb(float db)  { midEqDb.store(juce::jlimit(-24.0f, 12.0f, db)); }
    void setHighEqDb(float db) { highEqDb.store(juce::jlimit(-24.0f, 12.0f, db)); }
    void setFilter(float value) { filterAmount.store(juce::jlimit(-1.0f, 1.0f, value)); }
    void setChorusMix(float value) { chorusMix.store(juce::jlimit(0.0f, 1.0f, value)); }
    void setFlangerMix(float value) { flangerMix.store(juce::jlimit(0.0f, 1.0f, value)); }
    void setDualDelayMix(float value) { dualDelayMix.store(juce::jlimit(0.0f, 1.0f, value)); }
    void setFdnReverbMix(float value) { fdnReverbMix.store(juce::jlimit(0.0f, 1.0f, value)); }

    void prepare(double deviceSampleRate, int bufferSize);
    void release();

    void setReady(bool r);
    bool isReady() const;

    void resetPlaybackPosition();
    void setPlaybackPosition(int64_t pos);
    int64_t getPlaybackSamples() const;
    int64_t getProcessedSamples() const;

    int getStemAvailable(int idx) const;
    LookaheadBuffer* getInputBuffer();

    bool render(float* const* outputChannelData, int numOutputChannels, int numSamples, int ambisonicOrder);

    AmbisonicStemEncoder& getStemEncoder(int stemIdx)
    {
        return stemEncoders[static_cast<size_t>(juce::jlimit(0, 3, stemIdx))];
    }

    double getModelSampleRate() const { return modelSampleRate; }

    float getRms(int ch) const { return rms[ch].load(); }

    void setPlaybackRate(float r);
    float getPlaybackRate() const { return playbackRate.load(); }

    void clearBuffers(); // flush stems & input (usato per seek)

private:
    static constexpr double modelSampleRate = 44100.0;
    static constexpr int lookaheadCapacity = 343980 * 6;

    double deviceSampleRate = modelSampleRate;
    int deviceBufferSize = 512;

    juce::File modelFile;
    std::unique_ptr<LookaheadBuffer> inputBuffer;
    std::array<std::unique_ptr<LookaheadBuffer>, 4> stems;
    std::unique_ptr<SeparationWorker> worker;

    std::array<std::atomic<float>, 4> stemGains;
    std::array<std::atomic<bool>, 4> stemEnabled { true, true, true, true };
    std::atomic<bool> ready { false };
    std::atomic<int64_t> playbackSamples { 0 };

    bool needsResampling { false };
    double baseResampleRatio { 1.0 };
    std::array<std::unique_ptr<juce::LagrangeInterpolator>, AmbisonicStemEncoder::maxChannels> resamplers;
    std::array<AmbisonicStemEncoder, 4> stemEncoders;
    juce::AudioBuffer<float> mixSourceBuffer;
    juce::AudioBuffer<float> stemBuffer;

    std::array<std::atomic<float>, 2> rms { 0.0f, 0.0f };
    std::atomic<float> playbackRate { 1.0f };

    struct Biquad
    {
        float b0 { 1.0f }, b1 { 0.0f }, b2 { 0.0f };
        float a1 { 0.0f }, a2 { 0.0f };
        float z1 { 0.0f }, z2 { 0.0f };

        float process(float input) noexcept;
        void reset() noexcept { z1 = z2 = 0.0f; }
    };

    struct StemFilterChannel
    {
        Biquad low;
        Biquad mid;
        Biquad high;
        Biquad filter;

        void reset() noexcept;
        float process(float input, bool filterEnabled) noexcept;
    };

    std::atomic<float> lowEqDb { 0.0f };
    std::atomic<float> midEqDb { 0.0f };
    std::atomic<float> highEqDb { 0.0f };
    std::atomic<float> filterAmount { 0.0f };
    std::array<std::array<StemFilterChannel, 2>, 4> stemFilters;
    float currentLowEqDb { 100.0f };
    float currentMidEqDb { 100.0f };
    float currentHighEqDb { 100.0f };
    float currentFilterAmount { 100.0f };
    bool deckFilterEnabled { false };

    struct AmbisonicFdn
    {
        void prepare(double sampleRate, int numChannels);
        void reset();
        void process(float* const* output, int numChannels, int numSamples, float amount) noexcept;

        struct ChannelState
        {
            std::array<std::vector<float>, 4> delayLines;
            std::array<int, 4> positions {};
        };

        std::vector<ChannelState> channels;
        juce::SmoothedValue<float> wetMix;
    };

    struct AmbisonicDualDelay
    {
        void prepare(double sampleRate, int numChannels);
        void reset();
        void process(float* const* output, int numChannels, int numSamples, float amount) noexcept;

        struct ChannelState
        {
            std::array<std::vector<float>, 2> delayLines;
            std::array<int, 2> positions {};
        };

        std::vector<ChannelState> channels;
        juce::SmoothedValue<float> wetMix;
    };

    std::atomic<float> chorusMix { 0.0f };
    std::atomic<float> flangerMix { 0.0f };
    std::atomic<float> dualDelayMix { 0.0f };
    std::atomic<float> fdnReverbMix { 0.0f };
    std::array<juce::dsp::Chorus<float>, 4> stemChorus;
    std::array<juce::dsp::Chorus<float>, 4> stemFlanger;
    AmbisonicDualDelay ambisonicDualDelay;
    AmbisonicFdn ambisonicFdn;

    void clearOutput(float* const* outputChannelData, int numOutputChannels, int numSamples);
    void computeRms(const float* const* output, int numChannels, int numSamples);
    static Biquad makeLowPass(double sampleRate, double frequency);
    static Biquad makeHighPass(double sampleRate, double frequency);
    static Biquad makePeak(double sampleRate, double frequency, double gainDb);
    static Biquad makeShelf(double sampleRate, double frequency, double gainDb, bool highShelf);
    void updateFilterCoefficients();
    void processStemEffects(int stemIndex, int numSamples);
    void processAmbisonicEffects(float* const* output, int numChannels, int numSamples);
};