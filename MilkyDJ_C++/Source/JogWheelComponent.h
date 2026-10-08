#pragma once
#include <JuceHeader.h>

class JogWheelComponent : public juce::Component
{
public:
    JogWheelComponent();

    void paint(juce::Graphics& g) override;

    void mouseDown(const juce::MouseEvent& e) override;
    void mouseDrag(const juce::MouseEvent& e) override;
    void mouseUp(const juce::MouseEvent& e) override;

private:
    float angleRad { 0.0f };
    float lastAngleRad { 0.0f };
    bool dragging { false };

    float angleForPoint(juce::Point<float> p) const;
};