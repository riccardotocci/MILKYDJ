#include "HerculesInpulse200Midi.h"
#include "BrowserComponent.h"
#include "DeckComponent.h"
#include "MixerComponent.h"

namespace
{
    constexpr int midiValueOn = 0x7f;
    constexpr int midiValueOff = 0x00;
}

HerculesInpulse200Midi::HerculesInpulse200Midi(juce::AudioDeviceManager& deviceManager,
                                               DeckComponent& deckA,
                                               DeckComponent& deckB,
                                               MixerComponent& mixerComponent,
                                               BrowserComponent& browserComponent)
    : devices(deviceManager),
      decks { &deckA, &deckB },
      mixer(mixerComponent),
      browser(browserComponent)
{
    devices.addMidiInputDeviceCallback({}, this);
    refreshDevices();
    startTimerHz(10);
}

HerculesInpulse200Midi::~HerculesInpulse200Midi()
{
    alive->store(false);
    stopTimer();
    sendMidi(0xb0, 0x7f, 0x7e, true);
    sendMidi(0x90, 0x04, midiValueOff, true);
    devices.removeMidiInputDeviceCallback({}, this);
}

bool HerculesInpulse200Midi::isTargetDeviceName(const juce::String& name)
{
    const auto lower = name.toLowerCase();
    return lower.contains("inpulse 200")
        || (lower.contains("hercules") && lower.contains("djcontrol"));
}

int HerculesInpulse200Midi::relativeDelta(int value)
{
    value &= 0x7f;
    return value < 0x40 ? value : value - 0x80;
}

void HerculesInpulse200Midi::refreshDevices()
{
    bool foundInput = false;
    for (const auto& input : juce::MidiInput::getAvailableDevices())
    {
        if (!isTargetDeviceName(input.name))
            continue;

        foundInput = true;
        if (!devices.isMidiInputDeviceEnabled(input.identifier))
            devices.setMidiInputDeviceEnabled(input.identifier, true);
    }

    juce::String matchingOutput;
    for (const auto& output : juce::MidiOutput::getAvailableDevices())
    {
        if (isTargetDeviceName(output.name))
        {
            matchingOutput = output.identifier;
            break;
        }
    }

    const auto outputChanged = matchingOutput.isNotEmpty()
        && matchingOutput != outputIdentifier;
    if (outputChanged)
    {
        outputIdentifier = matchingOutput;
        devices.setDefaultMidiOutputDevice(outputIdentifier);
        lastLedValues.clear();
        sendStartupState();
    }
    else if (matchingOutput.isEmpty())
    {
        outputIdentifier.clear();
        lastLedValues.clear();
    }

    controllerConnected = foundInput;
}

void HerculesInpulse200Midi::handleIncomingMidiMessage(juce::MidiInput* source,
                                                        const juce::MidiMessage& message)
{
    if (source == nullptr || !isTargetDeviceName(source->getName())
        || message.getRawDataSize() < 3)
        return;

    const auto* data = message.getRawData();
    int status = data[0];
    const int control = data[1] & 0x7f;
    int value = data[2] & 0x7f;

    if ((status & 0xf0) == 0x80)
    {
        status += 0x10;
        value = 0;
    }

    auto lifetime = alive;
    juce::MessageManager::callAsync([this, lifetime, status, control, value]
    {
        if (lifetime->load())
            processMessage(status, control, value);
    });
}

void HerculesInpulse200Midi::processMessage(int status, int control, int value)
{
    if (status == 0x90 || status == 0x93)
    {
        if (value == 0)
            return;
        if (control == 0x00)
            browser.focusBrowser();
        else if (control == 0x03)
            browser.analyzeSelection();
        return;
    }

    if (status == 0x91 || status == 0x92)
    {
        processDeckButton(status - 0x91, false, control, value);
        return;
    }

    if (status == 0x94 || status == 0x95)
    {
        processDeckButton(status - 0x94, true, control, value);
        return;
    }

    if (status == 0x96 || status == 0x97)
    {
        processPad(status - 0x96, control, value);
        return;
    }

    if (status == 0xb0 || status == 0xb3)
    {
        if (control == 0x00 && status == 0xb0)
            mixer.setCrossfaderNormalized(value / 127.0f);
        else if (control == 0x01)
            browser.moveSelection(relativeDelta(value));
        return;
    }

    if (status == 0xb1 || status == 0xb2)
    {
        processDeckController(status - 0xb1, false, control, value);
        return;
    }

    if (status == 0xb4 || status == 0xb5)
        processDeckController(status - 0xb4, true, control, value);
}

void HerculesInpulse200Midi::processDeckButton(int deckIndex, bool shifted,
                                                int control, int value)
{
    auto& deck = *decks[static_cast<size_t>(deckIndex)];
    const bool pressed = value > 0;

    if (control == 0x08)
    {
        jogTouched[static_cast<size_t>(deckIndex)] = pressed;
        return;
    }

    if (!pressed && !(control == 0x06 && !shifted))
        return;

    if (shifted)
    {
        switch (control)
        {
            case 0x05: if (pressed) deck.sync(); break;
            case 0x06: if (pressed) deck.seekToStart(false); break;
            case 0x07: if (pressed) deck.seekToStart(true); break;
            case 0x09: if (pressed) deck.resizeLoop(0.5); break;
            case 0x0a: if (pressed) deck.resizeLoop(2.0); break;
            default: break;
        }
        return;
    }

    switch (control)
    {
        case 0x03:
            vinylMode[static_cast<size_t>(deckIndex)] = !vinylMode[static_cast<size_t>(deckIndex)];
            sendMidi(0x91 + deckIndex, 0x03,
                     vinylMode[static_cast<size_t>(deckIndex)] ? midiValueOn : midiValueOff);
            break;
        case 0x05: deck.sync(); break;
        case 0x06: pressed ? deck.pressCue() : deck.releaseCue(); break;
        case 0x07: deck.togglePlay(); break;
        case 0x09: deck.setLoopIn(); break;
        case 0x0a:
            deck.setLoopOut();
            if (!deck.getLoopEnabled())
                deck.toggleLoop();
            break;
        case 0x0c: mixer.toggleHeadphoneCue(deckIndex); break;
        case 0x0d: browser.loadSelectedIntoDeck(deckIndex); break;
        default: break;
    }
}

void HerculesInpulse200Midi::processPad(int deckIndex, int control, int value)
{
    auto& deck = *decks[static_cast<size_t>(deckIndex)];
    const bool pressed = value > 0;

    if (control >= 0x00 && control <= 0x03)
    {
        if (pressed)
            deck.triggerHotCue(control);
        return;
    }

    if (control >= 0x08 && control <= 0x0b)
    {
        if (pressed)
            deck.clearHotCue(control - 0x08);
        return;
    }

    if (control >= 0x10 && control <= 0x13)
    {
        if (pressed)
            deck.toggleStem(control - 0x10);
        return;
    }

    if ((control >= 0x20 && control <= 0x23)
        || (control >= 0x28 && control <= 0x2b))
    {
        if (pressed)
            deck.toggleEffect(control & 0x03);
        return;
    }

}

void HerculesInpulse200Midi::processDeckController(int deckIndex, bool shifted,
                                                    int control, int value)
{
    auto& deck = *decks[static_cast<size_t>(deckIndex)];
    const auto normalized = value / 127.0f;

    if (shifted)
    {
        if (control == 0x0a)
            deck.jogBySeconds(relativeDelta(value) * 0.12);
        return;
    }

    switch (control)
    {
        case 0x00: mixer.setDeckVolumeNormalized(deckIndex, normalized); break;
        case 0x01: mixer.setDeckFilterNormalized(deckIndex, normalized); break;
        case 0x02: mixer.setDeckEqNormalized(deckIndex, 0, normalized); break;
        case 0x04: mixer.setDeckEqNormalized(deckIndex, 2, normalized); break;
        case 0x05: mixer.setDeckTrimNormalized(deckIndex, normalized); break;
        case 0x08:
            pitchMsb[static_cast<size_t>(deckIndex)] = value;
            deck.setPitchNormalized((pitchMsb[static_cast<size_t>(deckIndex)] * 128
                                     + pitchLsb[static_cast<size_t>(deckIndex)]) / 16383.0f);
            break;
        case 0x28:
            pitchLsb[static_cast<size_t>(deckIndex)] = value;
            deck.setPitchNormalized((pitchMsb[static_cast<size_t>(deckIndex)] * 128
                                     + pitchLsb[static_cast<size_t>(deckIndex)]) / 16383.0f);
            break;
        case 0x09:
        case 0x0a:
        case 0x0c:
        {
            const auto sensitivity = jogTouched[static_cast<size_t>(deckIndex)]
                && vinylMode[static_cast<size_t>(deckIndex)] ? 0.055 : 0.018;
            deck.jogBySeconds(relativeDelta(value) * sensitivity);
            break;
        }
        default: break;
    }
}

void HerculesInpulse200Midi::sendMidi(int status, int control, int value, bool force)
{
    auto* output = devices.getDefaultMidiOutput();
    if (output == nullptr || outputIdentifier.isEmpty())
        return;

    const int key = (status << 8) | control;
    if (!force)
    {
        const auto previous = lastLedValues.find(key);
        if (previous != lastLedValues.end() && previous->second == value)
            return;
    }
    lastLedValues[key] = value;

    const juce::uint8 bytes[] {
        static_cast<juce::uint8>(status),
        static_cast<juce::uint8>(control),
        static_cast<juce::uint8>(value)
    };
    output->sendMessageNow(juce::MidiMessage(bytes, 3, 0.0));
}

void HerculesInpulse200Midi::sendStartupState()
{
    sendMidi(0xb0, 0x7f, 0x7f, true);
    sendMidi(0x90, 0x04, 0x05, true);
    for (int deckIndex = 0; deckIndex < 2; ++deckIndex)
        sendMidi(0x91 + deckIndex, 0x03, midiValueOn, true);
    updateLeds();
}

void HerculesInpulse200Midi::updateLeds()
{
    if (outputIdentifier.isEmpty())
        return;

    for (int deckIndex = 0; deckIndex < 2; ++deckIndex)
    {
        const auto& deck = *decks[static_cast<size_t>(deckIndex)];
        const int transportStatus = 0x91 + deckIndex;
        const int padStatus = 0x96 + deckIndex;
        sendMidi(transportStatus, 0x03,
                 vinylMode[static_cast<size_t>(deckIndex)] ? midiValueOn : midiValueOff);
        sendMidi(transportStatus, 0x05, midiValueOff);
        sendMidi(transportStatus, 0x06, deck.getCueHeld() ? midiValueOn : midiValueOff);
        sendMidi(transportStatus, 0x07, deck.getPlaying() ? midiValueOn : midiValueOff);
        sendMidi(transportStatus, 0x09, deck.getLoopEnabled() ? midiValueOn : midiValueOff);
        sendMidi(transportStatus, 0x0c,
                 mixer.getHeadphoneCueEnabled(deckIndex) ? midiValueOn : midiValueOff);

        for (int pad = 0; pad < 4; ++pad)
        {
            const auto hotCueValue = deck.hasHotCue(pad) ? 0x7e : midiValueOff;
            sendMidi(padStatus, pad, hotCueValue);
            sendMidi(padStatus, pad + 0x08, hotCueValue);
            const auto effectValue = deck.getEffectEnabled(pad) ? midiValueOn : midiValueOff;
            sendMidi(padStatus, pad + 0x20, effectValue);
            sendMidi(padStatus, pad + 0x28, effectValue);
            sendMidi(padStatus, pad + 0x10,
                     deck.getStemEnabled(pad) ? midiValueOn : midiValueOff);
        }
    }
}

void HerculesInpulse200Midi::timerCallback()
{
    if (--deviceScanCountdown <= 0)
    {
        deviceScanCountdown = 20;
        refreshDevices();
    }
    updateLeds();
}