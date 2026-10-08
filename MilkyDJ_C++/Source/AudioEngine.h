#pragma once
#include <array>
#include <atomic>
#include <juce_audio_basics/juce_audio_basics.h>
#include "AmbisonicConfigDecoder.h"
#include "AmbisonicEnergyMeter.h"
#include "BinauralMonitorDecoder.h"
#include "Deck.h"

class AudioEngine : public juce::AudioIODeviceCallback
{
public:
    AudioEngine();
    ~AudioEngine() { release(); }

    void setModelFile(const juce::File& f)
    {
        modelFile = f;
        decks[0].setModelFile(f);
        decks[1].setModelFile(f);
    }

    Deck& getDeck(int idx) { return decks[juce::jlimit(0, 1, idx)]; }
    AmbisonicStemEncoder& getStemEncoder(int deckIdx, int stemIdx)
    {
        return getDeck(deckIdx).getStemEncoder(stemIdx);
    }

    void setAmbisonicOrder(int order) { ambisonicOrder.store(juce::jlimit(1, 7, order)); }
    int getAmbisonicOrder() const { return ambisonicOrder.load(); }

    juce::Result loadDecoderConfiguration(const juce::File& file)
    {
        return decoder.loadConfiguration(file);
    }
    juce::String getDecoderName() const { return decoder.getConfigurationName(); }
    juce::String getDecoderPath() const { return decoder.getConfigurationPath(); }
    int getDecoderOutputChannels() const { return decoder.getConfiguredOutputChannels(); }

    void setCrossfader(float x) { crossfader.store(juce::jlimit(0.0f, 1.0f, x)); }
    void setMasterGain(float g)  { masterGain.store(g); }
    void setDeckGain(int idx, float g)
    {
        if (idx < 0 || idx > 1) return;
        deckGains[idx].store(g);
    }
    void setDeckTrimGain(int idx, float g)
    {
        if (idx < 0 || idx > 1) return;
        deckTrimGains[idx].store(juce::jlimit(0.0f, 2.0f, g));
    }
    void setHeadphoneEnabled(int idx, bool enabled)
    {
        if (idx >= 0 && idx < 2)
            headphoneEnabled[static_cast<size_t>(idx)].store(enabled);
    }
    void setHeadphoneVolume(int idx, float volume)
    {
        if (idx >= 0 && idx < 2)
            headphoneVolumes[static_cast<size_t>(idx)].store(juce::jlimit(0.0f, 1.0f, volume));
    }

    float getMasterRms(int ch) const { return masterRms[ch].load(); }
    float getEnergyLevel(int pointIndex) const { return energyMeter.getLevel(pointIndex); }

    void audioDeviceIOCallbackWithContext(const float* const* inputChannelData,
                                          int numInputChannels,
                                          float* const* outputChannelData,
                                          int numOutputChannels,
                                          int numSamples,
                                          const juce::AudioIODeviceCallbackContext& context) override;
    void audioDeviceAboutToStart(juce::AudioIODevice* device) override;
    void audioDeviceStopped() override;

private:
    juce::File modelFile;
    std::array<Deck, 2> decks;

    std::atomic<float> crossfader { 0.0f };
    std::atomic<float> masterGain { 1.0f };
    std::array<std::atomic<float>, 2> deckGains { 1.0f, 1.0f };
    std::array<std::atomic<float>, 2> deckTrimGains { 1.0f, 1.0f };
    std::array<std::atomic<bool>, 2> headphoneEnabled { false, false };
    std::array<std::atomic<float>, 2> headphoneVolumes { 0.7f, 0.7f };
    std::array<bool, 2> headphoneWasEnabled { false, false };
    std::atomic<int> ambisonicOrder { 3 };
    AmbisonicConfigDecoder decoder;
    std::array<BinauralMonitorDecoder, 2> binauralDecoders;
    AmbisonicEnergyMeter energyMeter;
    juce::dsp::Limiter<float> outputLimiter;

    std::array<std::atomic<float>, 2> masterRms { 0.0f, 0.0f };

    juce::AudioBuffer<float> deckBufferA;
    juce::AudioBuffer<float> deckBufferB;
    juce::AudioBuffer<float> ambisonicBuffer;
    std::array<juce::AudioBuffer<float>, 2> headphoneBuffers;

    void prepare(int sampleRate, int bufferSize);
    void release();
};