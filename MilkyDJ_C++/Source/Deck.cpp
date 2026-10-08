#include "Deck.h"
#include <cmath>

namespace
{
    constexpr double pi = juce::MathConstants<double>::pi;
}

Deck::Biquad Deck::makeLowPass(double sampleRate, double frequency)
{
        Biquad result;
        const auto omega = 2.0 * pi * frequency / sampleRate;
        const auto cosine = std::cos(omega);
        const auto alpha = std::sin(omega) / std::sqrt(2.0);
        const auto a0 = 1.0 + alpha;
        result.b0 = static_cast<float>((1.0 - cosine) * 0.5 / a0);
        result.b1 = static_cast<float>((1.0 - cosine) / a0);
        result.b2 = result.b0;
        result.a1 = static_cast<float>(-2.0 * cosine / a0);
        result.a2 = static_cast<float>((1.0 - alpha) / a0);
        return result;
    }

    Deck::Biquad Deck::makeHighPass(double sampleRate, double frequency)
    {
        Biquad result;
        const auto omega = 2.0 * pi * frequency / sampleRate;
        const auto cosine = std::cos(omega);
        const auto alpha = std::sin(omega) / std::sqrt(2.0);
        const auto a0 = 1.0 + alpha;
        result.b0 = static_cast<float>((1.0 + cosine) * 0.5 / a0);
        result.b1 = static_cast<float>(-(1.0 + cosine) / a0);
        result.b2 = result.b0;
        result.a1 = static_cast<float>(-2.0 * cosine / a0);
        result.a2 = static_cast<float>((1.0 - alpha) / a0);
        return result;
    }

    Deck::Biquad Deck::makePeak(double sampleRate, double frequency, double gainDb)
    {
        Biquad result;
        const auto amplitude = std::pow(10.0, gainDb / 40.0);
        const auto omega = 2.0 * pi * frequency / sampleRate;
        const auto cosine = std::cos(omega);
        const auto alpha = std::sin(omega) / (2.0 * 0.8);
        const auto a0 = 1.0 + alpha / amplitude;
        result.b0 = static_cast<float>((1.0 + alpha * amplitude) / a0);
        result.b1 = static_cast<float>(-2.0 * cosine / a0);
        result.b2 = static_cast<float>((1.0 - alpha * amplitude) / a0);
        result.a1 = static_cast<float>(-2.0 * cosine / a0);
        result.a2 = static_cast<float>((1.0 - alpha / amplitude) / a0);
        return result;
    }

    Deck::Biquad Deck::makeShelf(double sampleRate, double frequency, double gainDb, bool highShelf)
    {
        Biquad result;
        const auto amplitude = std::pow(10.0, gainDb / 40.0);
        const auto omega = 2.0 * pi * frequency / sampleRate;
        const auto cosine = std::cos(omega);
        const auto alpha = std::sin(omega) / std::sqrt(2.0);
        const auto twoRootAAlpha = 2.0 * std::sqrt(amplitude) * alpha;
        const auto plus = amplitude + 1.0;
        const auto minus = amplitude - 1.0;
        double a0 = 1.0;

        if (highShelf)
        {
            a0 = plus - minus * cosine + twoRootAAlpha;
            result.b0 = static_cast<float>(amplitude * (plus + minus * cosine + twoRootAAlpha) / a0);
            result.b1 = static_cast<float>(-2.0 * amplitude * (minus + plus * cosine) / a0);
            result.b2 = static_cast<float>(amplitude * (plus + minus * cosine - twoRootAAlpha) / a0);
            result.a1 = static_cast<float>(2.0 * (minus - plus * cosine) / a0);
            result.a2 = static_cast<float>((plus - minus * cosine - twoRootAAlpha) / a0);
        }
        else
        {
            a0 = plus + minus * cosine + twoRootAAlpha;
            result.b0 = static_cast<float>(amplitude * (plus - minus * cosine + twoRootAAlpha) / a0);
            result.b1 = static_cast<float>(2.0 * amplitude * (minus - plus * cosine) / a0);
            result.b2 = static_cast<float>(amplitude * (plus - minus * cosine - twoRootAAlpha) / a0);
            result.a1 = static_cast<float>(-2.0 * (minus + plus * cosine) / a0);
            result.a2 = static_cast<float>((plus + minus * cosine - twoRootAAlpha) / a0);
        }

        return result;
    }

float Deck::Biquad::process(float input) noexcept
{
    const auto output = b0 * input + z1;
    z1 = b1 * input - a1 * output + z2;
    z2 = b2 * input - a2 * output;
    return output;
}

void Deck::StemFilterChannel::reset() noexcept
{
    low.reset();
    mid.reset();
    high.reset();
    filter.reset();
}

float Deck::StemFilterChannel::process(float input, bool filterEnabled) noexcept
{
    auto output = high.process(mid.process(low.process(input)));
    return filterEnabled ? filter.process(output) : output;
}

void Deck::AmbisonicFdn::prepare(double sampleRate, int numChannels)
{
    static constexpr std::array<double, 4> delayTimesMs { 29.7, 37.1, 41.1, 53.3 };
    channels.resize(static_cast<size_t>(numChannels));

    for (int channel = 0; channel < numChannels; ++channel)
        for (int line = 0; line < 4; ++line)
        {
            const auto offsetMs = static_cast<double>((channel * 7 + line * 3) % 11) * 0.17;
            const auto length = std::max(2, static_cast<int>(
                std::round((delayTimesMs[static_cast<size_t>(line)] + offsetMs)
                           * sampleRate / 1000.0)));
            channels[static_cast<size_t>(channel)].delayLines[static_cast<size_t>(line)]
                .assign(static_cast<size_t>(length), 0.0f);
        }

    wetMix.reset(sampleRate, 0.05);
    wetMix.setCurrentAndTargetValue(0.0f);
}

void Deck::AmbisonicFdn::reset()
{
    for (auto& channel : channels)
    {
        channel.positions.fill(0);
        for (auto& line : channel.delayLines)
            std::fill(line.begin(), line.end(), 0.0f);
    }
}

void Deck::AmbisonicFdn::process(float* const* output, int numChannels,
                                 int numSamples, float amount) noexcept
{
    wetMix.setTargetValue(amount);
    const auto channelsToProcess = std::min(numChannels, static_cast<int>(channels.size()));

    for (int sample = 0; sample < numSamples; ++sample)
    {
        const auto mix = wetMix.getNextValue();
        for (int channel = 0; channel < channelsToProcess; ++channel)
        {
            auto& state = channels[static_cast<size_t>(channel)];
            std::array<float, 4> delayed {};
            for (int line = 0; line < 4; ++line)
                delayed[static_cast<size_t>(line)] =
                    state.delayLines[static_cast<size_t>(line)]
                                    [static_cast<size_t>(state.positions[static_cast<size_t>(line)])];

            const std::array<float, 4> feedback {
                0.5f * (delayed[0] + delayed[1] + delayed[2] + delayed[3]),
                0.5f * (delayed[0] - delayed[1] + delayed[2] - delayed[3]),
                0.5f * (delayed[0] + delayed[1] - delayed[2] - delayed[3]),
                0.5f * (delayed[0] - delayed[1] - delayed[2] + delayed[3])
            };

            const auto dry = output[channel][sample];
            for (int line = 0; line < 4; ++line)
            {
                auto& delayLine = state.delayLines[static_cast<size_t>(line)];
                auto& position = state.positions[static_cast<size_t>(line)];
                delayLine[static_cast<size_t>(position)] = 0.5f * dry
                    + 0.72f * feedback[static_cast<size_t>(line)];
                if (++position >= static_cast<int>(delayLine.size()))
                    position = 0;
            }

            const auto wet = 0.25f * (delayed[0] + delayed[1] + delayed[2] + delayed[3]);
            output[channel][sample] = dry + mix * (wet - dry);
        }
    }
}

void Deck::AmbisonicDualDelay::prepare(double sampleRate, int numChannels)
{
    static constexpr std::array<double, 2> delayTimesMs { 220.0, 365.0 };
    channels.resize(static_cast<size_t>(numChannels));

    for (auto& channel : channels)
        for (int line = 0; line < 2; ++line)
        {
            const auto length = std::max(2, static_cast<int>(
                std::round(delayTimesMs[static_cast<size_t>(line)] * sampleRate / 1000.0)));
            channel.delayLines[static_cast<size_t>(line)].assign(static_cast<size_t>(length), 0.0f);
        }

    wetMix.reset(sampleRate, 0.05);
    wetMix.setCurrentAndTargetValue(0.0f);
}

void Deck::AmbisonicDualDelay::reset()
{
    for (auto& channel : channels)
    {
        channel.positions.fill(0);
        for (auto& line : channel.delayLines)
            std::fill(line.begin(), line.end(), 0.0f);
    }
}

void Deck::AmbisonicDualDelay::process(float* const* output, int numChannels,
                                       int numSamples, float amount) noexcept
{
    wetMix.setTargetValue(amount);
    const auto channelsToProcess = std::min(numChannels, static_cast<int>(channels.size()));

    for (int sample = 0; sample < numSamples; ++sample)
    {
        const auto mix = wetMix.getNextValue();
        for (int channel = 0; channel < channelsToProcess; ++channel)
        {
            auto& state = channels[static_cast<size_t>(channel)];
            const auto dry = output[channel][sample];
            float wet = 0.0f;

            for (int line = 0; line < 2; ++line)
            {
                auto& delayLine = state.delayLines[static_cast<size_t>(line)];
                auto& position = state.positions[static_cast<size_t>(line)];
                const auto delayed = delayLine[static_cast<size_t>(position)];
                const auto feedback = line == 0 ? 0.32f : 0.42f;
                delayLine[static_cast<size_t>(position)] = dry + delayed * feedback;
                wet += 0.5f * delayed;
                if (++position >= static_cast<int>(delayLine.size()))
                    position = 0;
            }

            output[channel][sample] = dry + mix * (wet - dry);
        }
    }
}

Deck::Deck()
{
    for (auto& g : stemGains) g.store(1.0f);
}

Deck::~Deck()
{
    release();
}

void Deck::setModelFile(const juce::File& f)
{
    modelFile = f;
    if (worker && modelFile.existsAsFile())
        worker->setModel(modelFile);
}

void Deck::setStemGain(int stemIdx, float g)
{
    if (stemIdx >= 0 && stemIdx < static_cast<int>(stemGains.size()))
        stemGains[stemIdx].store(g);
}

void Deck::setPlaybackRate(float r)
{
    playbackRate.store(juce::jlimit(0.5f, 2.0f, r));
}

void Deck::prepare(double sr, int bufferSize)
{
    deviceSampleRate = sr;
    deviceBufferSize = bufferSize;

    inputBuffer = std::make_unique<LookaheadBuffer>(2, lookaheadCapacity);
    for (auto& s : stems)
        s = std::make_unique<LookaheadBuffer>(2, lookaheadCapacity);

    needsResampling = std::abs(deviceSampleRate - modelSampleRate) > 1.0;
    baseResampleRatio = modelSampleRate / deviceSampleRate;

    for (auto& resampler : resamplers)
    {
        resampler = std::make_unique<juce::LagrangeInterpolator>();
        resampler->reset();
    }

    mixSourceBuffer.setSize(AmbisonicStemEncoder::maxChannels, bufferSize * 8);
    stemBuffer.setSize(2, bufferSize * 8);

    for (auto& encoder : stemEncoders)
        encoder.reset();

    juce::dsp::ProcessSpec stemEffectSpec;
    stemEffectSpec.sampleRate = modelSampleRate;
    stemEffectSpec.maximumBlockSize = static_cast<juce::uint32>(bufferSize * 8);
    stemEffectSpec.numChannels = 2;
    for (int stem = 0; stem < 4; ++stem)
    {
        auto& chorus = stemChorus[static_cast<size_t>(stem)];
        chorus.prepare(stemEffectSpec);
        chorus.setRate(0.8f);
        chorus.setDepth(0.45f);
        chorus.setCentreDelay(8.0f);
        chorus.setFeedback(0.08f);

        auto& flanger = stemFlanger[static_cast<size_t>(stem)];
        flanger.prepare(stemEffectSpec);
        flanger.setRate(0.25f);
        flanger.setDepth(0.8f);
        flanger.setCentreDelay(2.0f);
        flanger.setFeedback(0.65f);
    }

    ambisonicDualDelay.prepare(deviceSampleRate, AmbisonicStemEncoder::maxChannels);
    ambisonicFdn.prepare(deviceSampleRate, AmbisonicStemEncoder::maxChannels);

    currentLowEqDb = currentMidEqDb = currentHighEqDb = currentFilterAmount = 100.0f;
    updateFilterCoefficients();

    worker = std::make_unique<SeparationWorker>(*inputBuffer, stems, bufferSize * 4);
    if (modelFile.existsAsFile())
        worker->setModel(modelFile);
    worker->start();
}

void Deck::release()
{
    if (worker) worker->stop();
    worker.reset();
    inputBuffer.reset();
    for (auto& s : stems) s.reset();
    for (auto& r : resamplers) r.reset();
}

void Deck::setReady(bool r) { ready.store(r); }
bool Deck::isReady() const { return ready.load(); }

void Deck::resetPlaybackPosition()
{
    playbackSamples.store(0);
    clearBuffers();
}

void Deck::setPlaybackPosition(int64_t pos)
{
    playbackSamples.store(pos);
    clearBuffers();
}

void Deck::clearBuffers()
{
    const bool restartWorker = worker != nullptr;
    if (restartWorker)
        worker->stop();
    if (inputBuffer) inputBuffer->clear();
    for (auto& s : stems)
        if (s) s->clear();
    for (auto& r : resamplers)
        if (r) r->reset();
    for (auto& stem : stemFilters)
        for (auto& channel : stem)
            channel.reset();
    for (auto& chorus : stemChorus)
        chorus.reset();
    for (auto& flanger : stemFlanger)
        flanger.reset();
    ambisonicDualDelay.reset();
    ambisonicFdn.reset();
    if (restartWorker)
        worker->start();
}

void Deck::updateFilterCoefficients()
{
    const auto nextLow = lowEqDb.load();
    const auto nextMid = midEqDb.load();
    const auto nextHigh = highEqDb.load();
    const auto nextFilter = filterAmount.load();

    if (nextLow == currentLowEqDb && nextMid == currentMidEqDb
        && nextHigh == currentHighEqDb && nextFilter == currentFilterAmount)
        return;

    currentLowEqDb = nextLow;
    currentMidEqDb = nextMid;
    currentHighEqDb = nextHigh;
    currentFilterAmount = nextFilter;

    const auto low = makeShelf(modelSampleRate, 120.0, currentLowEqDb, false);
    const auto mid = makePeak(modelSampleRate, 1000.0, currentMidEqDb);
    const auto high = makeShelf(modelSampleRate, 8000.0, currentHighEqDb, true);
    deckFilterEnabled = std::abs(currentFilterAmount) > 0.01f;

    Biquad filter;
    if (currentFilterAmount < -0.01f)
    {
        const auto cutoff = 20000.0 * std::pow(200.0 / 20000.0, -currentFilterAmount);
        filter = makeLowPass(modelSampleRate, cutoff);
    }
    else if (currentFilterAmount > 0.01f)
    {
        const auto cutoff = 20.0 * std::pow(15000.0 / 20.0, currentFilterAmount);
        filter = makeHighPass(modelSampleRate, cutoff);
    }

    for (auto& stem : stemFilters)
        for (auto& channel : stem)
        {
            channel.low = low;
            channel.mid = mid;
            channel.high = high;
            channel.filter = filter;
        }
}

void Deck::processStemEffects(int stemIndex, int numSamples)
{
    for (int channel = 0; channel < std::min(2, stemBuffer.getNumChannels()); ++channel)
    {
        auto* samples = stemBuffer.getWritePointer(channel);
        auto& filters = stemFilters[static_cast<size_t>(stemIndex)][static_cast<size_t>(channel)];
        for (int sample = 0; sample < numSamples; ++sample)
            samples[sample] = filters.process(samples[sample], deckFilterEnabled);
    }

    auto block = juce::dsp::AudioBlock<float>(stemBuffer).getSubBlock(
        0, static_cast<size_t>(numSamples));
    juce::dsp::ProcessContextReplacing<float> context(block);
    auto& chorus = stemChorus[static_cast<size_t>(stemIndex)];
    chorus.setMix(chorusMix.load());
    chorus.process(context);
    auto& flanger = stemFlanger[static_cast<size_t>(stemIndex)];
    flanger.setMix(flangerMix.load());
    flanger.process(context);
}

void Deck::processAmbisonicEffects(float* const* output, int numChannels, int numSamples)
{
    ambisonicDualDelay.process(output, numChannels, numSamples, dualDelayMix.load());
    ambisonicFdn.process(output, numChannels, numSamples, fdnReverbMix.load());
}

int64_t Deck::getPlaybackSamples() const { return playbackSamples.load(); }
int64_t Deck::getProcessedSamples() const { return worker ? worker->getProcessedSamples() : 0; }

int Deck::getStemAvailable(int idx) const
{
    if (idx < 0 || idx >= static_cast<int>(stems.size()) || stems[idx] == nullptr)
        return 0;
    return stems[idx]->getAvailable();
}

LookaheadBuffer* Deck::getInputBuffer() { return inputBuffer.get(); }

void Deck::clearOutput(float* const* outputChannelData, int numOutputChannels, int numSamples)
{
    for (int ch = 0; ch < numOutputChannels; ++ch)
        juce::FloatVectorOperations::clear(outputChannelData[ch], numSamples);
}

void Deck::computeRms(const float* const* output, int numChannels, int numSamples)
{
    const int chCount = std::min(numChannels, 2);
    for (int ch = 0; ch < chCount; ++ch)
    {
        const float* data = output[ch];
        double acc = 0.0;
        for (int i = 0; i < numSamples; ++i)
            acc += static_cast<double>(data[i]) * static_cast<double>(data[i]);
        float v = static_cast<float>(std::sqrt(acc / std::max(1, numSamples)));
        rms[ch].store(v);
    }
    for (int ch = chCount; ch < 2; ++ch)
        rms[ch].store(0.0f);
}

bool Deck::render(float* const* outputChannelData,
                  int numOutputChannels,
                  int numSamples,
                  int ambisonicOrder)
{
    if (inputBuffer == nullptr || stems[0] == nullptr || !ready.load())
    {
        clearOutput(outputChannelData, numOutputChannels, numSamples);
        computeRms((const float* const*)outputChannelData, numOutputChannels, numSamples);
        return false;
    }

    ambisonicOrder = juce::jlimit(1, AmbisonicStemEncoder::maxOrder, ambisonicOrder);
    const int maxChannels = std::min((ambisonicOrder + 1) * (ambisonicOrder + 1),
                                     numOutputChannels);

    const float rate = playbackRate.load();
    const double effectiveRatio = baseResampleRatio * std::max(0.0001, (double)rate);
    const bool useResampler = needsResampling || std::abs(effectiveRatio - 1.0) > 1e-4;
    updateFilterCoefficients();

    if (useResampler)
    {
        int sourceSamplesNeeded = static_cast<int>(std::ceil(numSamples * effectiveRatio)) + 4;

        for (int s = 0; s < 4; ++s)
            if (stems[s]->getAvailable() < sourceSamplesNeeded)
            {
                clearOutput(outputChannelData, numOutputChannels, numSamples);
                computeRms((const float* const*)outputChannelData, numOutputChannels, numSamples);
                return false;
            }

        mixSourceBuffer.setSize(maxChannels, sourceSamplesNeeded, false, false, true);
        mixSourceBuffer.clear();

        for (int stem = 0; stem < 4; ++stem)
        {
            stemBuffer.setSize(2, sourceSamplesNeeded, false, false, true);
            float* stemPtrs[2] = { stemBuffer.getWritePointer(0), stemBuffer.getWritePointer(1) };
            int got = stems[stem]->pop(stemPtrs, sourceSamplesNeeded);
            if (got <= 0) continue;

            processStemEffects(stem, got);

            stemEncoders[static_cast<size_t>(stem)].encodeAndAdd(
                stemBuffer, mixSourceBuffer, ambisonicOrder,
                stemEnabled[stem].load() ? stemGains[stem].load() : 0.0f, got);
        }

        for (int ch = 0; ch < maxChannels; ++ch)
        {
            resamplers[ch]->process(
                effectiveRatio,
                mixSourceBuffer.getReadPointer(ch),
                outputChannelData[ch],
                numSamples,
                mixSourceBuffer.getNumSamples(),
                false);
        }
        if (numOutputChannels > maxChannels)
            for (int ch = maxChannels; ch < numOutputChannels; ++ch)
                juce::FloatVectorOperations::clear(outputChannelData[ch], numSamples);
    }
    else
    {
        for (int s = 0; s < 4; ++s)
            if (stems[s]->getAvailable() < numSamples)
            {
                clearOutput(outputChannelData, numOutputChannels, numSamples);
                computeRms((const float* const*)outputChannelData, numOutputChannels, numSamples);
                return false;
            }

        for (int ch = 0; ch < numOutputChannels; ++ch)
            juce::FloatVectorOperations::clear(outputChannelData[ch], numSamples);

        for (int stem = 0; stem < 4; ++stem)
        {
            stemBuffer.setSize(2, numSamples, false, false, true);
            float* stemPtrs[2] = { stemBuffer.getWritePointer(0), stemBuffer.getWritePointer(1) };
            int got = stems[stem]->pop(stemPtrs, numSamples);
            if (got <= 0) continue;

            processStemEffects(stem, got);

            juce::AudioBuffer<float> outputBuffer(outputChannelData, maxChannels, numSamples);
            stemEncoders[static_cast<size_t>(stem)].encodeAndAdd(
                stemBuffer, outputBuffer, ambisonicOrder,
                stemEnabled[stem].load() ? stemGains[stem].load() : 0.0f, got);
        }
        if (numOutputChannels > maxChannels)
            for (int ch = maxChannels; ch < numOutputChannels; ++ch)
                juce::FloatVectorOperations::clear(outputChannelData[ch], numSamples);
    }

    processAmbisonicEffects(outputChannelData, maxChannels, numSamples);

    const auto sourceSamplesConsumed = static_cast<int64_t>(
        std::llround(numSamples * effectiveRatio));
    playbackSamples.fetch_add(sourceSamplesConsumed, std::memory_order_relaxed);
    computeRms((const float* const*)outputChannelData, numOutputChannels, numSamples);
    return true;
}