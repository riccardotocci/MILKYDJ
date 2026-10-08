#include "DeckComponent.h"
#include <JuceHeader.h>

namespace
{
    constexpr juce::uint32 stemColours[] = {
        0xffff6b5e, 0xffb8f34a, 0xff55d6be, 0xfff4b942
    };

    void styleButton(juce::Button& b, juce::Colour bg, juce::Colour fg)
    {
        b.setColour(juce::TextButton::buttonColourId, bg);
        b.setColour(juce::TextButton::buttonOnColourId, bg.brighter(0.12f));
        b.setColour(juce::TextButton::textColourOffId, fg);
        b.setColour(juce::TextButton::textColourOnId, fg);
    }
}

DeckComponent::DeckComponent(const juce::String& title, Deck& deck, juce::AudioFormatManager& fm)
    : deckTitle(title), deckRef(deck), formatManager(fm)
{
    setLookAndFeel(&lnf);

    addAndMakeVisible(loadButton);
    addAndMakeVisible(playPauseButton);
    addAndMakeVisible(cueButton);
    addAndMakeVisible(syncButton);
    addAndMakeVisible(loopInButton);
    addAndMakeVisible(loopOutButton);
    addAndMakeVisible(loopNudgeLeft);
    addAndMakeVisible(loopNudgeRight);
    addAndMakeVisible(loopEnableButton);

    const auto deckAccent = deckTitle.endsWithChar('A')
        ? juce::Colour(184, 243, 74)
        : juce::Colour(255, 107, 94);
    styleButton(loadButton, juce::Colour(59, 68, 64), juce::Colours::white);
    styleButton(playPauseButton, deckAccent.darker(0.18f), juce::Colours::white);
    styleButton(cueButton, juce::Colour(198, 143, 47), juce::Colours::white);
    styleButton(syncButton, juce::Colour(48, 153, 134), juce::Colours::white);
    styleButton(loopInButton, juce::Colour(47, 83, 76), juce::Colours::white);
    styleButton(loopOutButton, juce::Colour(128, 83, 51), juce::Colours::white);
    styleButton(loopNudgeLeft, juce::Colour(49, 57, 54), juce::Colours::white);
    styleButton(loopNudgeRight, juce::Colour(49, 57, 54), juce::Colours::white);
    loopEnableButton.setColour(juce::ToggleButton::tickColourId, deckAccent);

    playPauseButton.setEnabled(false);
    playPauseButton.setClickingTogglesState(true);

    loadButton.onClick = [this]{ loadTrack(); };
    playPauseButton.onClick = [this]{
        if (!bufferingReady || !analysisDone) return;
        isPlaying = playPauseButton.getToggleState();
        playPauseButton.setButtonText(isPlaying ? "PAUSE" : "PLAY");
        deckRef.setReady(isPlaying);
    };

    cueButton.setClickingTogglesState(false);
    cueButton.addMouseListener(this, false);

    syncButton.onClick = [this]{ syncToTarget(); };

    loopEnableButton.onClick = [this]{
        loopEnabled = loopEnableButton.getToggleState();
    };

    loopInButton.onClick = [this]{
        loopInSamples = deckRef.getPlaybackSamples();
        loopInSet = true;
        if (!loopOutSet) loopOutSamples = loopInSamples + minLoopSamples;
    };

    loopOutButton.onClick = [this]{
        loopOutSamples = deckRef.getPlaybackSamples();
        loopOutSet = true;
    };

    loopNudgeLeft.onClick = [this]{
        if (!loopOutSet || !loopInSet) return;
        int64_t shift = static_cast<int64_t>(deckRef.getModelSampleRate() * (nudgeMillis / 1000.0));
        loopOutSamples = std::max(loopInSamples + (int64_t)minLoopSamples, loopOutSamples - shift);
    };

    loopNudgeRight.onClick = [this]{
        if (!loopOutSet || !loopInSet) return;
        int64_t shift = static_cast<int64_t>(deckRef.getModelSampleRate() * (nudgeMillis / 1000.0));
        loopOutSamples = loopOutSamples + shift;
    };

    for (int i = 0; i < 4; ++i)
    {
        stemSliders[i].setRange(0.0, 2.0, 0.01);
        stemSliders[i].setValue(1.0);
        stemSliders[i].onValueChange = [this, i]{
            deckRef.setStemGain(i, (float) stemSliders[i].getValue());
        };
        stemSliders[i].setSliderStyle(juce::Slider::LinearVertical);
        stemSliders[i].setTextBoxStyle(juce::Slider::TextBoxBelow, false, 44, 18);
        stemSliders[i].setColour(juce::Slider::thumbColourId, juce::Colour(stemColours[i]));
        stemSliders[i].setLookAndFeel(&lnf);
        addAndMakeVisible(stemSliders[i]);

        stemButtons[i].setButtonText(stemNames[i]);
        stemButtons[i].setClickingTogglesState(true);
        stemButtons[i].setToggleState(true, juce::dontSendNotification);
        stemButtons[i].setColour(juce::TextButton::buttonColourId, juce::Colour(34, 40, 38));
        stemButtons[i].setColour(juce::TextButton::buttonOnColourId,
                                 juce::Colour(stemColours[i]).darker(0.42f));
        stemButtons[i].setColour(juce::TextButton::textColourOffId, juce::Colour(112, 122, 117));
        stemButtons[i].setColour(juce::TextButton::textColourOnId, juce::Colours::white);
        stemButtons[i].onClick = [this, i]{
            const auto enabled = stemButtons[i].getToggleState();
            deckRef.setStemEnabled(i, enabled);
            stemSliders[i].setColour(juce::Slider::thumbColourId,
                                     enabled ? juce::Colour(stemColours[i])
                                             : juce::Colour(88, 96, 92));
            stemSliders[i].repaint();
        };
        addAndMakeVisible(stemButtons[i]);
    }

    static constexpr const char* effectNames[] = {
        "CHORUS", "FLANGER", "DUAL DELAY", "FDN REVERB"
    };
    static constexpr juce::uint32 effectColours[] = {
        0xff55d6be, 0xff55d6be, 0xfff4b942, 0xfff4b942
    };
    for (int i = 0; i < 4; ++i)
    {
        effectSliders[i].setRange(0.0, 1.0, 0.01);
        effectSliders[i].setValue(0.0);
        effectSliders[i].setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
        effectSliders[i].setTextBoxStyle(juce::Slider::NoTextBox, false, 0, 0);
        effectSliders[i].setDoubleClickReturnValue(true, 0.0);
        effectSliders[i].setColour(juce::Slider::rotarySliderFillColourId,
                                   juce::Colour(effectColours[i]));
        effectSliders[i].setColour(juce::Slider::rotarySliderOutlineColourId,
                                   juce::Colour(52, 61, 57));
        effectSliders[i].setLookAndFeel(&lnf);
        addAndMakeVisible(effectSliders[i]);

        effectLabels[i].setText(effectNames[i], juce::dontSendNotification);
        effectLabels[i].setFont(juce::Font(9.5f, juce::Font::bold));
        effectLabels[i].setColour(juce::Label::textColourId, juce::Colour(180, 190, 185));
        effectLabels[i].setJustificationType(juce::Justification::centred);
        addAndMakeVisible(effectLabels[i]);
    }

    effectSliders[0].onValueChange = [this]{
        deckRef.setChorusMix((float) effectSliders[0].getValue());
    };
    effectSliders[1].onValueChange = [this]{
        deckRef.setFlangerMix((float) effectSliders[1].getValue());
    };
    effectSliders[2].onValueChange = [this]{
        deckRef.setDualDelayMix((float) effectSliders[2].getValue());
    };
    effectSliders[3].onValueChange = [this]{
        deckRef.setFdnReverbMix((float) effectSliders[3].getValue());
    };

    effectGroupLabels[0].setText("STEM FX - PRE ENCODER", juce::dontSendNotification);
    effectGroupLabels[1].setText("AMBISONIC FX - POST ENCODER", juce::dontSendNotification);
    for (auto& label : effectGroupLabels)
    {
        label.setFont(juce::Font(9.0f, juce::Font::bold));
        label.setColour(juce::Label::textColourId, juce::Colour(126, 138, 132));
        label.setJustificationType(juce::Justification::centred);
        addAndMakeVisible(label);
    }

    pitchSlider.setRange(-12.0, 12.0, 0.01);
    pitchSlider.setValue(0.0);
    pitchSlider.setSliderStyle(juce::Slider::LinearHorizontal);
    pitchSlider.setTextBoxStyle(juce::Slider::TextBoxRight, false, 48, 18);
    pitchSlider.setColour(juce::Slider::thumbColourId, deckAccent);
    pitchSlider.onValueChange = [this]{
        double semitones = pitchSlider.getValue();
        float rate = (float) std::pow(2.0, semitones / 12.0);
        deckRef.setPlaybackRate(rate);
    };
    pitchSlider.setLookAndFeel(&lnf);
    addAndMakeVisible(pitchSlider);
    pitchLabel.setText("TEMPO", juce::dontSendNotification);
    pitchLabel.setColour(juce::Label::textColourId, deckAccent);
    pitchLabel.setFont(juce::Font(12.0f, juce::Font::bold));
    pitchLabel.setJustificationType(juce::Justification::centredLeft);
    addAndMakeVisible(pitchLabel);

    addAndMakeVisible(vuMeter);

    startTimerHz(20);
}

DeckComponent::~DeckComponent()
{
    stopTimer();
    cueButton.removeMouseListener(this);
    analysisThread.reset();
    if (decoder) decoder->stopAndClear();
    setLookAndFeel(nullptr);
}

void DeckComponent::togglePlay()
{
    setPlaying(!isPlaying);
}

void DeckComponent::setPlaying(bool shouldPlay)
{
    if (shouldPlay && (!bufferingReady || !analysisDone))
        return;

    isPlaying = shouldPlay;
    cueHeld = false;
    playPauseButton.setToggleState(shouldPlay, juce::dontSendNotification);
    playPauseButton.setButtonText(shouldPlay ? "PAUSE" : "PLAY");
    deckRef.setReady(shouldPlay);
}

void DeckComponent::pressCue()
{
    if (!bufferingReady || !analysisDone)
        return;

    if (!hasCue)
    {
        cuePoint = deckRef.getPlaybackSamples();
        hasCue = true;
    }

    cueHeld = true;
    isPlaying = false;
    playPauseButton.setToggleState(false, juce::dontSendNotification);
    seekWithBuffering(cuePoint, true);
}

void DeckComponent::releaseCue()
{
    if (!cueHeld)
        return;

    if (hasCue)
        seekWithBuffering(cuePoint, false);
    cueHeld = false;
    isPlaying = false;
    playPauseButton.setToggleState(false, juce::dontSendNotification);
}

void DeckComponent::sync()
{
    syncToTarget();
}

void DeckComponent::setLoopIn()
{
    loopInSamples = deckRef.getPlaybackSamples();
    loopInSet = true;
    if (!loopOutSet)
        loopOutSamples = loopInSamples + minLoopSamples;
}

void DeckComponent::setLoopOut()
{
    loopOutSamples = deckRef.getPlaybackSamples();
    loopOutSet = true;
    if (loopOutSamples <= loopInSamples + minLoopSamples)
        loopOutSamples = loopInSamples + minLoopSamples;
}

void DeckComponent::toggleLoop()
{
    loopEnabled = !loopEnabled;
    loopEnableButton.setToggleState(loopEnabled, juce::dontSendNotification);
}

void DeckComponent::resizeLoop(double factor)
{
    if (!loopInSet || !loopOutSet || factor <= 0.0)
        return;

    const auto length = juce::jmax<int64_t>(minLoopSamples, loopOutSamples - loopInSamples);
    loopOutSamples = loopInSamples + juce::jmax<int64_t>(
        minLoopSamples, static_cast<int64_t>(std::llround(length * factor)));
}

void DeckComponent::setBeatLoop(double beats, bool active)
{
    if (!active)
    {
        loopEnabled = false;
        loopEnableButton.setToggleState(false, juce::dontSendNotification);
        return;
    }

    const auto effectiveBpm = bpm > 0.0 ? bpm * deckRef.getPlaybackRate() : 120.0;
    const auto length = static_cast<int64_t>(
        juce::jmax(1.0, beats) * 60.0 / effectiveBpm * deckRef.getModelSampleRate());
    loopInSamples = deckRef.getPlaybackSamples();
    loopOutSamples = loopInSamples + juce::jmax<int64_t>(minLoopSamples, length);
    loopInSet = true;
    loopOutSet = true;
    loopEnabled = true;
    loopEnableButton.setToggleState(true, juce::dontSendNotification);
}

void DeckComponent::jogBySeconds(double seconds)
{
    if (!decoder || trackTotalSamples <= 0)
        return;

    const auto delta = static_cast<int64_t>(seconds * deckRef.getModelSampleRate());
    const auto target = juce::jlimit<int64_t>(0, trackTotalSamples - 1,
                                              deckRef.getPlaybackSamples() + delta);
    seekWithBuffering(target, isPlaying || cueHeld);
}

void DeckComponent::seekToStart(bool startPlaying)
{
    if (!decoder)
        return;

    isPlaying = startPlaying;
    playPauseButton.setToggleState(startPlaying, juce::dontSendNotification);
    seekWithBuffering(0, startPlaying);
}

void DeckComponent::setPitchNormalized(float value)
{
    pitchSlider.setValue(juce::jmap(juce::jlimit(0.0f, 1.0f, value), -12.0f, 12.0f),
                         juce::sendNotificationSync);
}

void DeckComponent::triggerHotCue(int index)
{
    if (index < 0 || index >= static_cast<int>(hotCuePoints.size()) || !decoder)
        return;

    const auto slot = static_cast<size_t>(index);
    if (!hotCueSet[slot])
    {
        hotCuePoints[slot] = deckRef.getPlaybackSamples();
        hotCueSet[slot] = true;
        return;
    }

    seekWithBuffering(hotCuePoints[slot], isPlaying || cueHeld);
}

void DeckComponent::clearHotCue(int index)
{
    if (index >= 0 && index < static_cast<int>(hotCueSet.size()))
        hotCueSet[static_cast<size_t>(index)] = false;
}

void DeckComponent::toggleStem(int index)
{
    if (index < 0 || index >= 4)
        return;

    const auto enabled = !stemButtons[index].getToggleState();
    stemButtons[index].setToggleState(enabled, juce::sendNotificationSync);
}

void DeckComponent::toggleEffect(int index)
{
    if (index < 0 || index >= 4)
        return;

    effectSliders[index].setValue(effectSliders[index].getValue() > 0.0 ? 0.0 : 0.6,
                                  juce::sendNotificationSync);
}

bool DeckComponent::getStemEnabled(int index) const
{
    return index >= 0 && index < 4 && stemButtons[index].getToggleState();
}

bool DeckComponent::getEffectEnabled(int index) const
{
    return index >= 0 && index < 4 && effectSliders[index].getValue() > 0.0;
}

bool DeckComponent::hasHotCue(int index) const
{
    return index >= 0 && index < static_cast<int>(hotCueSet.size())
        && hotCueSet[static_cast<size_t>(index)];
}

void DeckComponent::drawMiniWaveform(juce::Graphics& g, juce::Rectangle<int> area)
{
    g.setColour(juce::Colour(10, 13, 13));
    g.fillRoundedRectangle(area.toFloat(), 6.0f);

    if (thumbnail.getNumChannels() == 0 || trackTotalSamples <= 0)
        return;

    const auto accent = deckTitle.endsWithChar('A')
        ? juce::Colour(184, 243, 74)
        : juce::Colour(255, 107, 94);
    g.setColour(accent.withAlpha(0.55f));
    thumbnail.drawChannels(g, area.reduced(3), 0.0, thumbnail.getTotalLength(), 1.0f);
}

void DeckComponent::paint(juce::Graphics& g)
{
    auto panel = getLocalBounds().toFloat().reduced(0.5f);
    g.setGradientFill(juce::ColourGradient(juce::Colour(26, 30, 28), 0.0f, 0.0f,
                                           juce::Colour(15, 18, 18), 0.0f, panel.getBottom(),
                                           false));
    g.fillRoundedRectangle(panel, 16.0f);
    g.setColour(juce::Colour(46, 54, 51));
    g.drawRoundedRectangle(panel, 16.0f, 1.0f);

    const auto accent = deckTitle.endsWithChar('A')
        ? juce::Colour(184, 243, 74)
        : juce::Colour(255, 107, 94);
    g.setGradientFill(juce::ColourGradient(accent, 0.0f, 0.0f,
                                           accent.withAlpha(0.15f), 0.0f, (float) getHeight(),
                                           false));
    g.fillRoundedRectangle(1.5f, 10.0f, 3.5f, getHeight() - 20.0f, 1.75f);

    g.setColour(accent);
    g.setFont(juce::Font(16.0f, juce::Font::bold));
    g.drawText(deckTitle.toUpperCase(), 16, 9, getWidth() - 32, 22,
               juce::Justification::centredLeft);

    auto mini = juce::Rectangle<int>(14, 36, getWidth() - 28, 24);
    drawMiniWaveform(g, mini);

    juce::String status;
    if (analysisInProgress)          status = "Analyzing BPM...";
    else if (decoder == nullptr)     status = "No track loaded";
    else if (! bufferingReady)
    {
        const auto pct = readyThresholdSamples > 0
            ? deckRef.getStemAvailable(0) / static_cast<float>(readyThresholdSamples) * 100.0f
            : 0.0f;
        status = "Buffering: " + juce::String(pct, 0) + "%";
    }
    else if (isPlaying || cueHeld)   status = "Playing";
    else                             status = "Ready";

    g.setColour(juce::Colour(151, 162, 157));
    g.setFont(12.5f);
    g.drawText(status, 14, 63, getWidth() - 28, 18, juce::Justification::centredLeft);

    g.setColour(juce::Colour(39, 46, 43));
    g.drawHorizontalLine(pitchLabel.getY() - 9, 16.0f, static_cast<float>(getWidth() - 16));
    if (effectGroupLabels[0].getY() > 0)
        g.drawHorizontalLine(effectGroupLabels[0].getY() - 6, 16.0f,
                             static_cast<float>(getWidth() - 16));

    g.setColour(juce::Colour(126, 138, 132));
    g.setFont(juce::Font(10.0f, juce::Font::bold));
    g.drawText("STEM CHANNELS", 16, stemButtons[0].getY() - 24, getWidth() - 32, 16,
               juce::Justification::centredLeft);
}

void DeckComponent::resized()
{
    auto area = getLocalBounds().reduced(16);
    area.removeFromTop(76);

    auto row1 = area.removeFromTop(38);
    const int row1Gap = 6;
    const int loadWidth = juce::jlimit(66, 84, row1.getWidth() / 4);
    loadButton.setBounds(row1.removeFromLeft(loadWidth));
    row1.removeFromLeft(row1Gap);
    const int transportWidth = (row1.getWidth() - row1Gap * 2) / 3;
    playPauseButton.setBounds(row1.removeFromLeft(transportWidth));
    row1.removeFromLeft(row1Gap);
    cueButton.setBounds(row1.removeFromLeft(transportWidth));
    row1.removeFromLeft(row1Gap);
    syncButton.setBounds(row1);

    area.removeFromTop(10);
    auto row2 = area.removeFromTop(32);
    const int row2Gap = 6;
    const int loopWidth = (row2.getWidth() - row2Gap * 4) / 5;
    loopInButton.setBounds(row2.removeFromLeft(loopWidth));
    row2.removeFromLeft(row2Gap);
    loopOutButton.setBounds(row2.removeFromLeft(loopWidth));
    row2.removeFromLeft(row2Gap);
    loopNudgeLeft.setBounds(row2.removeFromLeft(loopWidth));
    row2.removeFromLeft(row2Gap);
    loopNudgeRight.setBounds(row2.removeFromLeft(loopWidth));
    row2.removeFromLeft(row2Gap);
    loopEnableButton.setBounds(row2);

    area.removeFromTop(28);
    auto tempoArea = area.removeFromBottom(54);
    area.removeFromBottom(18);

    auto vuArea = area.removeFromRight(13);
    vuMeter.setBounds(vuArea.reduced(1, 2));
    area.removeFromRight(10);

    auto effectsArea = area.removeFromBottom(138);
    area.removeFromBottom(10);

    constexpr int stemGap = 8;
    const int stemWidth = (area.getWidth() - stemGap * 3) / 4;
    for (int i = 0; i < 4; ++i)
    {
        auto lane = area.removeFromLeft(stemWidth);
        stemButtons[i].setBounds(lane.removeFromTop(22));
        stemSliders[i].setBounds(lane);
        if (i < 3)
            area.removeFromLeft(stemGap);
    }

    constexpr int effectGroupGap = 10;
    auto preEffects = effectsArea.removeFromLeft((effectsArea.getWidth() - effectGroupGap) / 2);
    effectsArea.removeFromLeft(effectGroupGap);
    auto postEffects = effectsArea;

    auto placeEffectGroup = [this](juce::Rectangle<int> group, int groupIndex, int firstEffect)
    {
        effectGroupLabels[groupIndex].setBounds(group.removeFromTop(18));
        const int controlWidth = group.getWidth() / 2;
        for (int control = 0; control < 2; ++control)
        {
            auto cell = control == 0 ? group.removeFromLeft(controlWidth) : group;
            const int effectIndex = firstEffect + control;
            effectLabels[effectIndex].setBounds(cell.removeFromTop(17));
            effectSliders[effectIndex].setBounds(cell.reduced(5, 0));
        }
    };
    placeEffectGroup(preEffects, 0, 0);
    placeEffectGroup(postEffects, 1, 2);

    pitchLabel.setBounds(tempoArea.removeFromLeft(54));
    tempoArea.removeFromLeft(8);
    pitchSlider.setBounds(tempoArea);
}

void DeckComponent::timerCallback()
{
    updateStatus();
    performLoopIfNeeded();
    playPauseButton.setButtonText(playPauseButton.getToggleState() ? "PAUSE" : "PLAY");
    float level = std::max(deckRef.getRms(0), deckRef.getRms(1));
    vuMeter.setLevel(level);
    repaint();
}

void DeckComponent::performLoopIfNeeded()
{
    if (!loopEnabled || !loopInSet || !loopOutSet) return;
    if (loopOutSamples <= loopInSamples + minLoopSamples) return;
    if (!bufferingReady) return;

    auto pos = deckRef.getPlaybackSamples();
    if (pos >= loopOutSamples)
        seekWithBuffering(loopInSamples, isPlaying);
}

void DeckComponent::seekWithBuffering(int64_t targetSamples, bool shouldResume)
{
    if (! decoder)
        return;

    deckRef.setReady(false);
    bufferingReady = false;
    resumeWhenBuffered = shouldResume;
    decoder->stopAndClear();
    deckRef.setPlaybackPosition(targetSamples);
    decoder->seekToSamples(targetSamples);
}

int64_t DeckComponent::getPhaseAlignedSample(const DeckComponent& target) const
{
    if (beatTimes.size() < 2 || target.beatTimes.size() < 2)
        return deckRef.getPlaybackSamples();

    const auto findBeatPair = [](const std::vector<double>& beats, double position)
    {
        auto next = std::upper_bound(beats.begin(), beats.end(), position);
        if (next == beats.begin())
            return std::pair<double, double>(beats[0], beats[1]);
        if (next == beats.end())
            return std::pair<double, double>(beats[beats.size() - 2], beats.back());
        return std::pair<double, double>(*(next - 1), *next);
    };

    const auto targetPair = findBeatPair(target.beatTimes, target.getPlaybackSeconds());
    const auto targetBeatLength = std::max(0.001, targetPair.second - targetPair.first);
    const auto phase = juce::jlimit(0.0, 1.0,
                                    (target.getPlaybackSeconds() - targetPair.first) / targetBeatLength);

    const auto ownPair = findBeatPair(beatTimes, getPlaybackSeconds());
    const auto alignedSeconds = ownPair.first + phase * (ownPair.second - ownPair.first);
    return static_cast<int64_t>(alignedSeconds * deckRef.getModelSampleRate());
}

void DeckComponent::syncToTarget()
{
    if (syncTarget == nullptr || ! analysisDone || ! syncTarget->analysisDone
        || bpm <= 0.0 || syncTarget->bpm <= 0.0)
        return;

    const auto targetBpm = syncTarget->bpm * syncTarget->deckRef.getPlaybackRate();
    const auto rate = juce::jlimit(0.5, 2.0, targetBpm / bpm);
    deckRef.setPlaybackRate(static_cast<float>(rate));
    pitchSlider.setValue(12.0 * std::log2(rate), juce::dontSendNotification);

    seekWithBuffering(getPhaseAlignedSample(*syncTarget), isPlaying || cueHeld);
}

void DeckComponent::updateStatus()
{
    if (!decoder || deckRef.getInputBuffer() == nullptr)
    {
        playPauseButton.setEnabled(false);
        bufferingReady = false;
        return;
    }

    if (!bufferingReady && readyThresholdSamples > 0)
    {
        auto avail = deckRef.getStemAvailable(0);
        if (avail >= readyThresholdSamples) {
            bufferingReady = true;
            if (resumeWhenBuffered)
            {
                resumeWhenBuffered = false;
                deckRef.setReady(true);
            }
        }
    }

    playPauseButton.setEnabled(bufferingReady && analysisDone);
}

void DeckComponent::loadTrack()
{
    fileChooser = std::make_unique<juce::FileChooser>(
        "Select an audio file",
        juce::File{},
        "*.wav;*.mp3;*.aiff;*.flac"
    );

    auto chooserFlags = juce::FileBrowserComponent::openMode | juce::FileBrowserComponent::canSelectFiles;

    fileChooser->launchAsync(chooserFlags, [this](const juce::FileChooser& fc)
    {
        auto file = fc.getResult();
        if (file == juce::File{})
            return;
        doLoadFile(file);
    });
}

void DeckComponent::loadFile(const juce::File& file)
{
    if (file == juce::File{})
        return;
    doLoadFile(file);
}

void DeckComponent::startAnalysis(const juce::File& file)
{
    analysisThread.reset();
    analysisInProgress = true;
    analysisDone = false;
    beatTimes.clear();
    bpm = 0.0;

    juce::Component::SafePointer<DeckComponent> safeThis(this);
    analysisThread = std::make_unique<BpmAnalysisThread>(
        file,
        [safeThis, file](BpmAnalysisResult result) mutable
        {
            if (safeThis != nullptr)
                safeThis->finishAnalysis(file, std::move(result));
        });
    analysisThread->start();
}

void DeckComponent::finishAnalysis(const juce::File& file, BpmAnalysisResult result)
{
    if (file != loadedFile)
        return;

    bpm = result.bpm;
    beatTimes = std::move(result.beatTimes);
    analysisInProgress = false;
    analysisDone = true;
    analysisThread.reset();
}

void DeckComponent::doLoadFile(const juce::File& file)
{
    constexpr double modelSampleRate = 44100.0;

    loadedFile = file;

    readyThresholdSamples = static_cast<int>(OnnxSeparator::DEMUCS_WINDOW);

    bufferingReady = false;
    resumeWhenBuffered = false;
    isPlaying = false;
    cueHeld = false;
    hasCue = false;
    cuePoint = 0;
    hotCuePoints.fill(0);
    hotCueSet.fill(false);
    loopInSet = false;
    loopOutSet = false;
    loopEnabled = false;
    loopEnableButton.setToggleState(false, juce::dontSendNotification);

    deckRef.setReady(false);
    if (decoder)
        decoder->stopAndClear();
    deckRef.resetPlaybackPosition();
    playPauseButton.setToggleState(false, juce::dontSendNotification);
    playPauseButton.setEnabled(false);

    thumbnail.clear();
    thumbnail.setSource(new juce::FileInputSource(file));

    decoder = std::make_unique<TrackDecoder>(formatManager, *deckRef.getInputBuffer(), 2);
    decoder->loadAndStart(file, modelSampleRate);

    if (auto* reader = formatManager.createReaderFor(file))
    {
        double ratio = reader->sampleRate / modelSampleRate;
        trackTotalSamples = static_cast<int64_t>(reader->lengthInSamples / ratio);
        delete reader;
    }

    startAnalysis(file);
}

void DeckComponent::mouseDown(const juce::MouseEvent& e)
{
    if (e.eventComponent == &cueButton)
        pressCue();
}

void DeckComponent::mouseUp(const juce::MouseEvent& e)
{
    if (e.eventComponent == &cueButton)
        releaseCue();
}