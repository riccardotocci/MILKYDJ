#pragma once

#include <JuceHeader.h>
#include "AudioEngine.h"
#include "DJLookAndFeel.h"

class SpatialMixerComponent : public juce::Component, private juce::Timer
{
public:
    explicit SpatialMixerComponent(AudioEngine& engineRef);
    ~SpatialMixerComponent() override;

    void paint(juce::Graphics& graphics) override;
    void resized() override;
    void mouseDown(const juce::MouseEvent& event) override;
    void mouseDrag(const juce::MouseEvent& event) override;

private:
    static constexpr int numSources = 8;

    AmbisonicStemEncoder& getEncoder(int sourceIndex) const;
    juce::Point<float> sourceToPoint(int sourceIndex) const;
    void updateSelectedSource(juce::Point<float> position);
    void selectSource(int sourceIndex);
    void loadDecoder();
    void timerCallback() override;

    AudioEngine& engine;
    DJLookAndFeel lookAndFeel;
    juce::Rectangle<int> mapBounds;
    int selectedSource = 0;

    juce::ComboBox orderSelector;
    juce::Slider azimuthSlider;
    juce::Slider elevationSlider;
    juce::Slider widthSlider;
    juce::TextButton loadDecoderButton { "LOAD DECODER CONFIG" };
    juce::Label orderLabel { {}, "ORDER" };
    juce::Label azimuthLabel { {}, "AZIMUTH" };
    juce::Label elevationLabel { {}, "ELEVATION" };
    juce::Label widthLabel { {}, "WIDTH" };
    juce::Label selectedLabel;
    juce::Label decoderLabel;
    std::unique_ptr<juce::FileChooser> fileChooser;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(SpatialMixerComponent)
};
