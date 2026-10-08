#pragma once
#include <JuceHeader.h>
#include "AudioEngine.h"
#include "EnergyVisualizerComponent.h"
#include "VUMeter.h"
#include "DJLookAndFeel.h"

class MixerComponent : public juce::Component, private juce::Timer
{
public:
    MixerComponent(AudioEngine& engineRef,
                   Deck& deckARef,
                   Deck& deckBRef,
                   std::function<void()> openSpatialMixer);

    void resized() override;
    void paint(juce::Graphics&) override;

    void setCrossfaderNormalized(float value);
    void setMasterNormalized(float value);
    void setDeckVolumeNormalized(int deckIndex, float value);
    void setDeckTrimNormalized(int deckIndex, float value);
    void setDeckEqNormalized(int deckIndex, int bandIndex, float value);
    void setDeckFilterNormalized(int deckIndex, float value);
    void toggleHeadphoneCue(int deckIndex);
    bool getHeadphoneCueEnabled(int deckIndex) const;

private:
    AudioEngine& engine;
    Deck& deckA;
    Deck& deckB;

    DJLookAndFeel lnf;

    juce::Slider crossfader;
    juce::Slider master;
    juce::Slider deckGainA;
    juce::Slider deckGainB;
    juce::TextButton headphoneButtons[2];
    juce::Slider headphoneVolumes[2];
    juce::Slider deckFilters[2][4];
    juce::Label deckFilterLabels[2][4];
    juce::TextButton spatialMixerButton { "SPATIAL MIXER" };

    juce::Label  labelA { "VolA", "VOL A" };
    juce::Label  labelB { "VolB", "VOL B" };
    juce::Label  labelXf { "XF", "CROSS" };
    juce::Label  labelM { "Master", "MASTER" };

    VUMeter vuA;
    VUMeter vuB;
    VUMeter vuMaster;
    EnergyVisualizerComponent energyVisualizer;

    void setupSlider(juce::Slider& s, double min, double max, double init, bool vertical);
    void setupDeckFilter(int deckIndex, int filterIndex, const juce::String& name,
                         double min, double max, double initialValue);
    void timerCallback() override;
};