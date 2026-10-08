#pragma once

#include <JuceHeader.h>
#include "AudioEngine.h"

class EnergyVisualizerComponent : public juce::Component
{
public:
    explicit EnergyVisualizerComponent(const AudioEngine& engineRef);
    void paint(juce::Graphics& graphics) override;

private:
    static juce::Point<float> projectHammerAitoff(float azimuthDegrees,
                                                  float elevationDegrees,
                                                  juce::Rectangle<float> bounds);
    static juce::Colour levelColour(float normalizedLevel);

    const AudioEngine& engine;
};
