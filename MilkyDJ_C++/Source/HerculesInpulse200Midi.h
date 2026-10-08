#pragma once
#include <JuceHeader.h>
#include <array>
#include <atomic>
#include <map>
#include <memory>

class BrowserComponent;
class DeckComponent;
class MixerComponent;

class HerculesInpulse200Midi : private juce::MidiInputCallback,
                               private juce::Timer
{
public:
    HerculesInpulse200Midi(juce::AudioDeviceManager& deviceManager,
                           DeckComponent& deckA,
                           DeckComponent& deckB,
                           MixerComponent& mixer,
                           BrowserComponent& browser);
    ~HerculesInpulse200Midi() override;

    bool isConnected() const { return controllerConnected; }

private:
    void handleIncomingMidiMessage(juce::MidiInput* source,
                                   const juce::MidiMessage& message) override;
    void timerCallback() override;

    void refreshDevices();
    void processMessage(int status, int control, int value);
    void processDeckButton(int deckIndex, bool shifted, int control, int value);
    void processPad(int deckIndex, int control, int value);
    void processDeckController(int deckIndex, bool shifted, int control, int value);
    void updateLeds();
    void sendMidi(int status, int control, int value, bool force = false);
    void sendStartupState();

    static bool isTargetDeviceName(const juce::String& name);
    static int relativeDelta(int value);

    juce::AudioDeviceManager& devices;
    std::array<DeckComponent*, 2> decks;
    MixerComponent& mixer;
    BrowserComponent& browser;

    std::array<int, 2> pitchMsb { 64, 64 };
    std::array<int, 2> pitchLsb { 0, 0 };
    std::array<bool, 2> vinylMode { true, true };
    std::array<bool, 2> jogTouched { false, false };
    std::map<int, int> lastLedValues;
    juce::String outputIdentifier;
    int deviceScanCountdown { 0 };
    bool controllerConnected { false };
    std::shared_ptr<std::atomic<bool>> alive { std::make_shared<std::atomic<bool>>(true) };

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(HerculesInpulse200Midi)
};