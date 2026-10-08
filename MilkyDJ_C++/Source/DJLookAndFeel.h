#pragma once
#include <JuceHeader.h>

class DJLookAndFeel : public juce::LookAndFeel_V4
{
public:
    DJLookAndFeel();

    void drawButtonBackground(juce::Graphics& g, juce::Button& b,
                              const juce::Colour& background,
                              bool shouldDrawButtonAsHighlighted,
                              bool shouldDrawButtonAsDown) override;

    void drawButtonText(juce::Graphics& g, juce::TextButton& button,
                        bool shouldDrawButtonAsHighlighted,
                        bool shouldDrawButtonAsDown) override;

    void drawLinearSlider(juce::Graphics& g, int x, int y, int width, int height,
                          float sliderPos, float minSliderPos, float maxSliderPos,
                          const juce::Slider::SliderStyle style, juce::Slider& slider) override;

    void drawToggleButton(juce::Graphics& g, juce::ToggleButton& button,
                          bool shouldDrawButtonAsHighlighted,
                          bool shouldDrawButtonAsDown) override;

private:
    std::unique_ptr<juce::Drawable> verticalKnob;
    std::unique_ptr<juce::Drawable> horizontalKnob;
};