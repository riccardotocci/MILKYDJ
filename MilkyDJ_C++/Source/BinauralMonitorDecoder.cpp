#include "BinauralMonitorDecoder.h"
#include "../JuceLibraryCode/BinaryData.h"

#include <cmath>

namespace
{
    constexpr int sourceImpulseLength = 236;

    constexpr int midChannelIndices[36] = {
        0, 2, 3, 6, 7, 8, 12, 13, 14, 15, 20, 21,
        22, 23, 24, 30, 31, 32, 33, 34, 35, 42, 43, 44,
        45, 46, 47, 48, 56, 57, 58, 59, 60, 61, 62, 63
    };

    constexpr int sideChannelIndices[28] = {
        1, 4, 5, 9, 10, 11, 16, 17, 18, 19, 25, 26, 27, 28,
        29, 36, 37, 38, 39, 40, 41, 49, 50, 51, 52, 53, 54, 55
    };
}

const void* BinauralMonitorDecoder::getImpulseResource(int order, int& dataSize)
{
    switch (order)
    {
        case 1: dataSize = BinaryData::irsOrd1_wavSize; return BinaryData::irsOrd1_wav;
        case 2: dataSize = BinaryData::irsOrd2_wavSize; return BinaryData::irsOrd2_wav;
        case 3: dataSize = BinaryData::irsOrd3_wavSize; return BinaryData::irsOrd3_wav;
        case 4: dataSize = BinaryData::irsOrd4_wavSize; return BinaryData::irsOrd4_wav;
        case 5: dataSize = BinaryData::irsOrd5_wavSize; return BinaryData::irsOrd5_wav;
        case 6: dataSize = BinaryData::irsOrd6_wavSize; return BinaryData::irsOrd6_wav;
        case 7: dataSize = BinaryData::irsOrd7_wavSize; return BinaryData::irsOrd7_wav;
        default: dataSize = 0; return nullptr;
    }
}

void BinauralMonitorDecoder::prepare(double newSampleRate, int maximumBlockSize)
{
    preparedBlockSize = maximumBlockSize;
    impulseLength = juce::roundToInt(sourceImpulseLength * newSampleRate / 44100.0);
    fftLength = juce::nextPowerOfTwo(preparedBlockSize + impulseLength - 1);
    fft = std::make_unique<juce::dsp::FFT>(juce::roundToInt(std::log2(fftLength)));
    fftBuffer.resize(static_cast<size_t>(fftLength));
    accumulatedMid.resize(static_cast<size_t>(fftLength));
    accumulatedSide.resize(static_cast<size_t>(fftLength));
    overlapBuffer.setSize(2, impulseLength - 1);

    juce::WavAudioFormat wavFormat;
    for (int order = 1; order <= 7; ++order)
    {
        int resourceSize = 0;
        const auto* resourceData = getImpulseResource(order, resourceSize);
        auto stream = std::make_unique<juce::MemoryInputStream>(resourceData,
                                                                static_cast<size_t>(resourceSize),
                                                                false);
        std::unique_ptr<juce::AudioFormatReader> reader(wavFormat.createReaderFor(stream.release(), true));
        auto& data = orderData[static_cast<size_t>(order - 1)];
        data.numChannels = (order + 1) * (order + 1);
        data.numSideChannels = order * (order + 1) / 2;
        data.numMidChannels = data.numChannels - data.numSideChannels;
        data.frequencyDomainIrs.setSize(data.numChannels, fftLength + 2);
        data.frequencyDomainIrs.clear();

        if (reader == nullptr)
            continue;

        juce::AudioBuffer<float> source(data.numChannels, sourceImpulseLength);
        reader->read(&source, 0, sourceImpulseLength, 0, true, false);
        source.applyGain(0.3f);

        for (int channel = 0; channel < data.numChannels; ++channel)
        {
            auto* scratch = reinterpret_cast<float*>(fftBuffer.data());
            juce::FloatVectorOperations::clear(scratch, fftLength * 2);

            if (impulseLength == sourceImpulseLength)
            {
                juce::FloatVectorOperations::copy(scratch, source.getReadPointer(channel), impulseLength);
            }
            else
            {
                juce::LagrangeInterpolator interpolator;
                interpolator.process(44100.0 / newSampleRate,
                                     source.getReadPointer(channel), scratch,
                                     impulseLength, sourceImpulseLength, true);
                juce::FloatVectorOperations::multiply(
                    scratch, static_cast<float>(44100.0 / newSampleRate), impulseLength);
            }

            fft->performRealOnlyForwardTransform(scratch);
            juce::FloatVectorOperations::copy(data.frequencyDomainIrs.getWritePointer(channel),
                                              scratch, fftLength + 2);
        }
    }

    reset();
}

void BinauralMonitorDecoder::reset()
{
    overlapBuffer.clear();
    previousOrder = 0;
}

void BinauralMonitorDecoder::process(const juce::AudioBuffer<float>& ambisonicInput,
                                     int order,
                                     juce::AudioBuffer<float>& stereoOutput)
{
    const int numSamples = juce::jmin(ambisonicInput.getNumSamples(), preparedBlockSize);
    stereoOutput.clear();
    if (fft == nullptr || numSamples <= 0 || stereoOutput.getNumChannels() < 2)
        return;

    order = juce::jlimit(1, 7, order);
    if (previousOrder != order)
    {
        overlapBuffer.clear();
        previousOrder = order;
    }

    const auto& data = orderData[static_cast<size_t>(order - 1)];
    const int numChannels = juce::jmin(data.numChannels, ambisonicInput.getNumChannels());
    auto* mid = reinterpret_cast<float*>(accumulatedMid.data());
    auto* side = reinterpret_cast<float*>(accumulatedSide.data());
    juce::FloatVectorOperations::clear(mid, fftLength + 2);
    juce::FloatVectorOperations::clear(side, fftLength + 2);

    const auto accumulate = [this, &ambisonicInput, &data, numSamples, numChannels]
        (const int* indices, int count, std::complex<float>* destination)
    {
        for (int index = 0; index < count; ++index)
        {
            const int channel = indices[index];
            if (channel >= numChannels)
                continue;

            auto* scratch = reinterpret_cast<float*>(fftBuffer.data());
            juce::FloatVectorOperations::clear(scratch, fftLength * 2);
            juce::FloatVectorOperations::copy(scratch,
                                              ambisonicInput.getReadPointer(channel),
                                              numSamples);
            const int degree = static_cast<int>(std::sqrt(static_cast<float>(channel)));
            juce::FloatVectorOperations::multiply(
                scratch, std::sqrt(static_cast<float>(2 * degree + 1)), numSamples);
            fft->performRealOnlyForwardTransform(scratch);

            const auto* transfer = reinterpret_cast<const std::complex<float>*>(
                data.frequencyDomainIrs.getReadPointer(channel));
            for (int bin = 0; bin < fftLength / 2 + 1; ++bin)
                destination[bin] += fftBuffer[static_cast<size_t>(bin)] * transfer[bin];
        }
    };

    accumulate(midChannelIndices, data.numMidChannels, accumulatedMid.data());
    accumulate(sideChannelIndices, data.numSideChannels, accumulatedSide.data());
    fft->performRealOnlyInverseTransform(mid);
    fft->performRealOnlyInverseTransform(side);

    auto* left = stereoOutput.getWritePointer(0);
    auto* right = stereoOutput.getWritePointer(1);
    const int overlapLength = impulseLength - 1;
    const int overlapToCopy = juce::jmin(numSamples, overlapLength);
    for (int sample = 0; sample < numSamples; ++sample)
    {
        const auto overlapLeft = sample < overlapLength ? overlapBuffer.getSample(0, sample) : 0.0f;
        const auto overlapRight = sample < overlapLength ? overlapBuffer.getSample(1, sample) : 0.0f;
        left[sample] = mid[sample] + side[sample] + overlapLeft;
        right[sample] = mid[sample] - side[sample] + overlapRight;
    }

    if (numSamples < overlapLength)
    {
        const int remaining = overlapLength - numSamples;
        for (int channel = 0; channel < 2; ++channel)
        {
            juce::FloatVectorOperations::copy(overlapBuffer.getWritePointer(channel),
                                              overlapBuffer.getReadPointer(channel, numSamples),
                                              remaining);
            juce::FloatVectorOperations::clear(overlapBuffer.getWritePointer(channel, remaining),
                                               overlapLength - remaining);
        }
    }
    else
    {
        overlapBuffer.clear();
    }

    juce::FloatVectorOperations::add(overlapBuffer.getWritePointer(0), mid + numSamples,
                                     overlapToCopy);
    juce::FloatVectorOperations::add(overlapBuffer.getWritePointer(0), side + numSamples,
                                     overlapToCopy);
    juce::FloatVectorOperations::add(overlapBuffer.getWritePointer(1), mid + numSamples,
                                     overlapToCopy);
    juce::FloatVectorOperations::subtract(overlapBuffer.getWritePointer(1), side + numSamples,
                                          overlapToCopy);
}