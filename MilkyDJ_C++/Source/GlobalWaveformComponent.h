#pragma once
#include <JuceHeader.h>
#include "DeckComponent.h"

class GlobalWaveformComponent : public juce::Component,
                                private juce::Timer
{
public:
    GlobalWaveformComponent(DeckComponent& a, DeckComponent& b);

    void paint(juce::Graphics& g) override;

private:
    void timerCallback() override;
    void drawZoomedWaveform(juce::Graphics& g, juce::Rectangle<int> area,
                            DeckComponent& deck, juce::Colour accent);

    DeckComponent& deckA;
    DeckComponent& deckB;

    float windowSeconds = 8.0f; // zoom window
};