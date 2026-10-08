#pragma once
#include <JuceHeader.h>
#include "AudioEngine.h"
#include "TrackDecoder.h"
#include "DeckComponent.h"
#include "MixerComponent.h"
#include "BrowserComponent.h"
#include "GlobalWaveformComponent.h"
#include "SpatialMixerComponent.h"
#include "MilkyLogoComponent.h"
#include "HerculesInpulse200Midi.h"

class MainComponent : public juce::Component
{
public:
    MainComponent();
    ~MainComponent() override;

    void paint(juce::Graphics&) override;
    void resized() override;
    void showAudioMidiSettings();

private:
    juce::AudioDeviceManager deviceManager;
    AudioEngine engine;
    juce::AudioFormatManager formatManager;

    std::unique_ptr<DeckComponent> deckAComp;
    std::unique_ptr<DeckComponent> deckBComp;
    std::unique_ptr<MixerComponent> mixerComp;
    std::unique_ptr<BrowserComponent> browserComp;
    std::unique_ptr<GlobalWaveformComponent> waveformComp;
    std::unique_ptr<juce::DocumentWindow> spatialMixerWindow;
    std::unique_ptr<juce::DocumentWindow> audioSettingsWindow;
    MilkyLogoComponent logo;
    std::unique_ptr<HerculesInpulse200Midi> midiController;

    void showSpatialMixer();
    juce::File getAudioSettingsFile() const;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(MainComponent)
};