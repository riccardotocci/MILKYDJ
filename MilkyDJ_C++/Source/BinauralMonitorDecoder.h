#pragma once

#include <array>
#include <complex>
#include <memory>
#include <vector>
#include <JuceHeader.h>

class BinauralMonitorDecoder
{
public:
    void prepare(double newSampleRate, int maximumBlockSize);
    void reset();
    void process(const juce::AudioBuffer<float>& ambisonicInput,
                 int order,
                 juce::AudioBuffer<float>& stereoOutput);

private:
    struct OrderData
    {
        int numChannels { 0 };
        int numMidChannels { 0 };
        int numSideChannels { 0 };
        juce::AudioBuffer<float> frequencyDomainIrs;
    };

    std::array<OrderData, 7> orderData;
    std::vector<std::complex<float>> fftBuffer;
    std::vector<std::complex<float>> accumulatedMid;
    std::vector<std::complex<float>> accumulatedSide;
    std::unique_ptr<juce::dsp::FFT> fft;
    juce::AudioBuffer<float> overlapBuffer;
    int fftLength { 0 };
    int impulseLength { 0 };
    int preparedBlockSize { 0 };
    int previousOrder { 0 };

    static const void* getImpulseResource(int order, int& dataSize);
};