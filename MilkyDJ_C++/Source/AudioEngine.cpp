/*
  ==============================================================================

    AudioEngine.cpp
    Created: 1 Feb 2026 3:35:30pm
    Author:  Riccardo Tocci

  ==============================================================================
*/

#include "AudioEngine.h"

AudioEngine::AudioEngine()
{
    static constexpr float initialAzimuths[] = {
        -70.0f, -25.0f, 25.0f, 70.0f, -110.0f, -145.0f, 145.0f, 110.0f
    };
    for (int source = 0; source < 8; ++source)
        getStemEncoder(source / 4, source % 4).setPosition(
            initialAzimuths[source], source < 4 ? 20.0f : -20.0f);
}

static void computeRms(const float* const* data, int numChannels, int numSamples, std::array<std::atomic<float>,2>& dest)
{
    int chCount = std::min(numChannels, 2);
    for (int ch = 0; ch < chCount; ++ch)
    {
        const float* d = data[ch];
        double acc = 0.0;
        for (int i = 0; i < numSamples; ++i)
            acc += static_cast<double>(d[i]) * static_cast<double>(d[i]);
        dest[ch].store(static_cast<float>(std::sqrt(acc / std::max(1, numSamples))));
    }
    for (int ch = chCount; ch < 2; ++ch)
        dest[ch].store(0.0f);
}

void AudioEngine::prepare(int sampleRate, int bufferSize)
{
    decks[0].prepare(sampleRate, bufferSize);
    decks[1].prepare(sampleRate, bufferSize);

    deckBufferA.setSize(AmbisonicStemEncoder::maxChannels, bufferSize * 2);
    deckBufferB.setSize(AmbisonicStemEncoder::maxChannels, bufferSize * 2);
    ambisonicBuffer.setSize(AmbisonicStemEncoder::maxChannels, bufferSize * 2);
    for (int deck = 0; deck < 2; ++deck)
    {
        headphoneBuffers[static_cast<size_t>(deck)].setSize(2, bufferSize * 2);
        binauralDecoders[static_cast<size_t>(deck)].prepare(sampleRate, bufferSize * 2);
        headphoneWasEnabled[static_cast<size_t>(deck)] = false;
    }
    energyMeter.prepare(sampleRate, bufferSize);

    juce::dsp::ProcessSpec limiterSpec;
    limiterSpec.sampleRate = sampleRate;
    limiterSpec.maximumBlockSize = static_cast<juce::uint32>(bufferSize * 2);
    limiterSpec.numChannels = 64;
    outputLimiter.prepare(limiterSpec);
    outputLimiter.setThreshold(-1.0f);
    outputLimiter.setRelease(80.0f);
}

void AudioEngine::release()
{
    decks[0].release();
    decks[1].release();
    for (auto& binauralDecoder : binauralDecoders)
        binauralDecoder.reset();
    energyMeter.reset();
    outputLimiter.reset();
}

void AudioEngine::audioDeviceIOCallbackWithContext(const float* const* inputChannelData,
                                                   int numInputChannels,
                                                   float* const* outputChannelData,
                                                   int numOutputChannels,
                                                   int numSamples,
                                                   const juce::AudioIODeviceCallbackContext& context)
{
    juce::ignoreUnused(inputChannelData, numInputChannels, context);

    for (int ch = 0; ch < numOutputChannels; ++ch)
        juce::FloatVectorOperations::clear(outputChannelData[ch], numSamples);

    const int order = ambisonicOrder.load();
    const int numAmbisonicChannels = (order + 1) * (order + 1);
    deckBufferA.setSize(numAmbisonicChannels, numSamples, false, false, true);
    deckBufferB.setSize(numAmbisonicChannels, numSamples, false, false, true);
    ambisonicBuffer.setSize(numAmbisonicChannels, numSamples, false, false, true);
    deckBufferA.clear();
    deckBufferB.clear();
    ambisonicBuffer.clear();

    float* deckAOut[AmbisonicStemEncoder::maxChannels] = {};
    float* deckBOut[AmbisonicStemEncoder::maxChannels] = {};
    for (int ch = 0; ch < deckBufferA.getNumChannels(); ++ch)
    {
        deckAOut[ch] = deckBufferA.getWritePointer(ch);
        deckBOut[ch] = deckBufferB.getWritePointer(ch);
    }

    decks[0].render(deckAOut, deckBufferA.getNumChannels(), numSamples, order);
    decks[1].render(deckBOut, deckBufferB.getNumChannels(), numSamples, order);

    const juce::AudioBuffer<float>* deckBuffers[] = { &deckBufferA, &deckBufferB };
    for (int deck = 0; deck < 2; ++deck)
    {
        const auto enabled = headphoneEnabled[static_cast<size_t>(deck)].load();
        auto& headphoneBuffer = headphoneBuffers[static_cast<size_t>(deck)];
        headphoneBuffer.clear();
        if (enabled)
        {
            if (! headphoneWasEnabled[static_cast<size_t>(deck)])
                binauralDecoders[static_cast<size_t>(deck)].reset();
            binauralDecoders[static_cast<size_t>(deck)].process(
                *deckBuffers[deck], order, headphoneBuffer);
        }
        headphoneWasEnabled[static_cast<size_t>(deck)] = enabled;
    }

    const float xf      = crossfader.load();
    const float master  = masterGain.load();
    const float wA      = (1.0f - xf) * deckGains[0].load() * deckTrimGains[0].load();
    const float wB      = xf * deckGains[1].load() * deckTrimGains[1].load();

    for (int ch = 0; ch < numAmbisonicChannels; ++ch)
    {
        juce::FloatVectorOperations::addWithMultiply(
            ambisonicBuffer.getWritePointer(ch), deckBufferA.getReadPointer(ch), wA * master, numSamples);
        juce::FloatVectorOperations::addWithMultiply(
            ambisonicBuffer.getWritePointer(ch), deckBufferB.getReadPointer(ch), wB * master, numSamples);
    }

    energyMeter.process(ambisonicBuffer, order);
    decoder.process(ambisonicBuffer, outputChannelData, numOutputChannels, numSamples);

    const bool canRouteHeadphones = numOutputChannels >= 4
        && decoder.getConfiguredOutputChannels() <= 2;
    for (int deck = 0; deck < 2 && canRouteHeadphones; ++deck)
    {
        if (! headphoneEnabled[static_cast<size_t>(deck)].load())
            continue;

        const auto volume = headphoneVolumes[static_cast<size_t>(deck)].load();
        for (int channel = 0; channel < 2; ++channel)
            juce::FloatVectorOperations::addWithMultiply(
                outputChannelData[channel + 2],
                headphoneBuffers[static_cast<size_t>(deck)].getReadPointer(channel),
                volume, numSamples);
    }

    juce::dsp::AudioBlock<float> outputBlock(
        outputChannelData, static_cast<size_t>(numOutputChannels), static_cast<size_t>(numSamples));
    juce::dsp::ProcessContextReplacing<float> limiterContext(outputBlock);
    outputLimiter.process(limiterContext);

    computeRms((const float* const*)outputChannelData, numOutputChannels, numSamples, masterRms);
}

void AudioEngine::audioDeviceAboutToStart(juce::AudioIODevice* device)
{
    prepare(static_cast<int>(device->getCurrentSampleRate()),
            device->getCurrentBufferSizeSamples());
}

void AudioEngine::audioDeviceStopped()
{
    release();
}