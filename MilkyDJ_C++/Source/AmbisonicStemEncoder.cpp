#include "AmbisonicStemEncoder.h"

#include <cmath>

void SHEval0(float, float, float, float*);
void SHEval1(float, float, float, float*);
void SHEval2(float, float, float, float*);
void SHEval3(float, float, float, float*);
void SHEval4(float, float, float, float*);
void SHEval5(float, float, float, float*);
void SHEval6(float, float, float, float*);
void SHEval7(float, float, float, float*);

namespace
{
    void evaluateN3D(int order, float x, float y, float z, float* coefficients)
    {
        using Evaluator = void (*)(float, float, float, float*);
        static constexpr Evaluator evaluators[] = {
            SHEval0, SHEval1, SHEval2, SHEval3, SHEval4, SHEval5, SHEval6, SHEval7
        };
        evaluators[static_cast<size_t>(order)](x, y, z, coefficients);
        juce::FloatVectorOperations::multiply(coefficients,
                                              3.544907701811032f,
                                              (order + 1) * (order + 1));
    }
}

AmbisonicStemEncoder::AmbisonicStemEncoder() = default;

void AmbisonicStemEncoder::setPosition(float azimuthDegrees, float elevationDegrees)
{
    azimuth.store(juce::jlimit(-180.0f, 180.0f, azimuthDegrees));
    elevation.store(juce::jlimit(-90.0f, 90.0f, elevationDegrees));
}

void AmbisonicStemEncoder::setWidth(float widthDegrees)
{
    width.store(juce::jlimit(0.0f, 180.0f, widthDegrees));
}

void AmbisonicStemEncoder::reset()
{
    previousLeft.fill(0.0f);
    previousRight.fill(0.0f);
    currentLeft.fill(0.0f);
    currentRight.fill(0.0f);
    coefficientsReady = false;
}

void AmbisonicStemEncoder::updateCoefficients(int order)
{
    order = juce::jlimit(0, maxOrder, order);
    const auto centreAzimuth = juce::degreesToRadians(azimuth.load());
    const auto sourceElevation = juce::degreesToRadians(elevation.load());
    const auto halfWidth = juce::degreesToRadians(width.load() * 0.5f);
    const auto cosElevation = std::cos(sourceElevation);

    const auto evaluate = [order, sourceElevation, cosElevation](float sourceAzimuth,
                                                                 std::array<float, maxChannels>& coefficients)
    {
        const float x = cosElevation * std::cos(sourceAzimuth);
        const float y = cosElevation * std::sin(sourceAzimuth);
        const float z = std::sin(sourceElevation);
        evaluateN3D(order, x, y, z, coefficients.data());

        const int numChannels = (order + 1) * (order + 1);
        for (int channel = 0; channel < numChannels; ++channel)
        {
            const int degree = static_cast<int>(std::sqrt(static_cast<float>(channel)));
            coefficients[static_cast<size_t>(channel)] /= std::sqrt(static_cast<float>(2 * degree + 1));
        }
    };

    evaluate(centreAzimuth + halfWidth, currentLeft);
    evaluate(centreAzimuth - halfWidth, currentRight);

    if (! coefficientsReady)
    {
        previousLeft = currentLeft;
        previousRight = currentRight;
        coefficientsReady = true;
    }
}

void AmbisonicStemEncoder::encodeAndAdd(const juce::AudioBuffer<float>& stereoInput,
                                        juce::AudioBuffer<float>& ambisonicOutput,
                                        int order,
                                        float gain,
                                        int numSamples)
{
    if (stereoInput.getNumChannels() < 2 || numSamples <= 0)
        return;

    order = juce::jlimit(0, maxOrder, order);
    updateCoefficients(order);

    const int numChannels = juce::jmin((order + 1) * (order + 1), ambisonicOutput.getNumChannels());
    const auto* left = stereoInput.getReadPointer(0);
    const auto* right = stereoInput.getReadPointer(1);

    for (int channel = 0; channel < numChannels; ++channel)
    {
        auto* destination = ambisonicOutput.getWritePointer(channel);
        juce::FloatVectorOperations::addWithMultiply(destination,
                                                     left,
                                                     gain * previousLeft[static_cast<size_t>(channel)],
                                                     numSamples);
        juce::FloatVectorOperations::addWithMultiply(destination,
                                                     right,
                                                     gain * previousRight[static_cast<size_t>(channel)],
                                                     numSamples);

        const float leftStep = gain * (currentLeft[static_cast<size_t>(channel)]
                                       - previousLeft[static_cast<size_t>(channel)])
                               / static_cast<float>(numSamples);
        const float rightStep = gain * (currentRight[static_cast<size_t>(channel)]
                                        - previousRight[static_cast<size_t>(channel)])
                                / static_cast<float>(numSamples);
        float leftCorrection = 0.0f;
        float rightCorrection = 0.0f;
        for (int sample = 0; sample < numSamples; ++sample)
        {
            destination[sample] += left[sample] * leftCorrection + right[sample] * rightCorrection;
            leftCorrection += leftStep;
            rightCorrection += rightStep;
        }
    }

    previousLeft = currentLeft;
    previousRight = currentRight;
}
