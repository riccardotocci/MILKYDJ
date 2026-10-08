#pragma once

#include <JuceHeader.h>
#include <array>
#include <atomic>

class AmbisonicStemEncoder
{
public:
    static constexpr int maxOrder = 7;
    static constexpr int maxChannels = 64;

    AmbisonicStemEncoder();

    void setPosition(float azimuthDegrees, float elevationDegrees);
    void setWidth(float widthDegrees);

    float getAzimuth() const { return azimuth.load(); }
    float getElevation() const { return elevation.load(); }
    float getWidth() const { return width.load(); }

    void reset();
    void encodeAndAdd(const juce::AudioBuffer<float>& stereoInput,
                      juce::AudioBuffer<float>& ambisonicOutput,
                      int order,
                      float gain,
                      int numSamples);

private:
    void updateCoefficients(int order);

    std::atomic<float> azimuth { 0.0f };
    std::atomic<float> elevation { 0.0f };
    std::atomic<float> width { 60.0f };
    std::array<float, maxChannels> previousLeft {};
    std::array<float, maxChannels> previousRight {};
    std::array<float, maxChannels> currentLeft {};
    std::array<float, maxChannels> currentRight {};
    bool coefficientsReady = false;
};
