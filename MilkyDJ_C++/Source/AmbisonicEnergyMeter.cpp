#include "AmbisonicEnergyMeter.h"
#include "../../resources_inpiu/MaxRE.h"

#include <cmath>

void SHEval7(float, float, float, float*);

namespace
{
    constexpr float sqrtFourPi = 3.544907701811032f;

    int degreeForChannel(int channel)
    {
        return static_cast<int>(std::sqrt(static_cast<float>(channel)));
    }
}

AmbisonicEnergyMeter::AmbisonicEnergyMeter()
{
    for (int point = 0; point < numPoints; ++point)
    {
        const float azimuth = juce::degreesToRadians(getAzimuth(point));
        const float elevation = juce::degreesToRadians(getElevation(point));
        const float cosElevation = std::cos(elevation);
        auto& row = decoderMatrix[static_cast<size_t>(point)];
        SHEval7(cosElevation * std::cos(azimuth),
                cosElevation * std::sin(azimuth),
                std::sin(elevation),
                row.data());

        for (int channel = 0; channel < maxChannels; ++channel)
            row[static_cast<size_t>(channel)] *= std::sqrt(static_cast<float>(2 * degreeForChannel(channel) + 1));
    }
    reset();
}

void AmbisonicEnergyMeter::prepare(double sampleRate, int maximumBlockSize)
{
    const double blockDuration = maximumBlockSize / juce::jmax(1.0, sampleRate);
    smoothing = static_cast<float>(std::exp(-blockDuration / 0.12));
    reset();
}

void AmbisonicEnergyMeter::reset()
{
    for (auto& level : levels)
        level.store(0.0f, std::memory_order_relaxed);
}

void AmbisonicEnergyMeter::process(const juce::AudioBuffer<float>& ambisonicInput, int order)
{
    order = juce::jlimit(1, 7, order);
    const int numChannels = juce::jmin((order + 1) * (order + 1), ambisonicInput.getNumChannels());
    const int numSamples = ambisonicInput.getNumSamples();
    if (numChannels <= 0 || numSamples <= 0)
        return;

    std::array<float, maxChannels> weights {};
    copyMaxRE(order, weights.data());
    const float correction = maxRECorrection[order] * sqrtFourPi
                             / static_cast<float>((order + 1) * (order + 1));
    for (int channel = 0; channel < numChannels; ++channel)
        weights[static_cast<size_t>(channel)] *= correction;

    const int sampleStride = juce::jmax(1, numSamples / 32);
    const float oneMinusSmoothing = 1.0f - smoothing;
    for (int point = 0; point < numPoints; ++point)
    {
        const auto& row = decoderMatrix[static_cast<size_t>(point)];
        double sumSquares = 0.0;
        int measuredSamples = 0;
        for (int sample = 0; sample < numSamples; sample += sampleStride)
        {
            float directionalSample = 0.0f;
            for (int channel = 0; channel < numChannels; ++channel)
                directionalSample += ambisonicInput.getSample(channel, sample)
                                     * row[static_cast<size_t>(channel)]
                                     * weights[static_cast<size_t>(channel)];
            sumSquares += static_cast<double>(directionalSample) * directionalSample;
            ++measuredSamples;
        }

        const float rms = static_cast<float>(std::sqrt(sumSquares / juce::jmax(1, measuredSamples)));
        const float previous = levels[static_cast<size_t>(point)].load(std::memory_order_relaxed);
        levels[static_cast<size_t>(point)].store(smoothing * previous + oneMinusSmoothing * rms,
                                                 std::memory_order_relaxed);
    }
}

float AmbisonicEnergyMeter::getLevel(int pointIndex) const
{
    pointIndex = juce::jlimit(0, numPoints - 1, pointIndex);
    return levels[static_cast<size_t>(pointIndex)].load(std::memory_order_relaxed);
}

float AmbisonicEnergyMeter::getAzimuth(int pointIndex)
{
    const int column = juce::jlimit(0, numPoints - 1, pointIndex) % azimuthBands;
    return -180.0f + (static_cast<float>(column) + 0.5f) * (360.0f / azimuthBands);
}

float AmbisonicEnergyMeter::getElevation(int pointIndex)
{
    const int row = juce::jlimit(0, numPoints - 1, pointIndex) / azimuthBands;
    return -75.0f + static_cast<float>(row) * 25.0f;
}
