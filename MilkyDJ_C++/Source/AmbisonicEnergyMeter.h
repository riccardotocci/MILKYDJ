#pragma once

#include <JuceHeader.h>
#include <array>
#include <atomic>

class AmbisonicEnergyMeter
{
public:
    static constexpr int azimuthBands = 16;
    static constexpr int elevationBands = 7;
    static constexpr int numPoints = azimuthBands * elevationBands;
    static constexpr int maxChannels = 64;

    AmbisonicEnergyMeter();

    void prepare(double sampleRate, int maximumBlockSize);
    void reset();
    void process(const juce::AudioBuffer<float>& ambisonicInput, int order);

    float getLevel(int pointIndex) const;
    static float getAzimuth(int pointIndex);
    static float getElevation(int pointIndex);

private:
    std::array<std::array<float, maxChannels>, numPoints> decoderMatrix {};
    std::array<std::atomic<float>, numPoints> levels {};
    float smoothing = 0.0f;
};
