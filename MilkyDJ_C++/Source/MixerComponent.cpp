#include "MixerComponent.h"

MixerComponent::MixerComponent(AudioEngine& engineRef,
                               Deck& deckARef,
                               Deck& deckBRef,
                               std::function<void()> openSpatialMixer)
    : engine(engineRef), deckA(deckARef), deckB(deckBRef), energyVisualizer(engineRef)
{
    setLookAndFeel(&lnf);

    setupSlider(crossfader, 0.0, 1.0, 0.0, false);
    crossfader.onValueChange = [this]{ engine.setCrossfader((float) crossfader.getValue()); };

    setupSlider(master, 0.0, 2.0, 1.0, false);
    master.onValueChange = [this]{ engine.setMasterGain((float) master.getValue()); };

    setupSlider(deckGainA, 0.0, 2.0, 1.0, true);
    deckGainA.onValueChange = [this]{ engine.setDeckGain(0, (float) deckGainA.getValue()); };

    setupSlider(deckGainB, 0.0, 2.0, 1.0, true);
    deckGainB.onValueChange = [this]{ engine.setDeckGain(1, (float) deckGainB.getValue()); };

    crossfader.setColour(juce::Slider::thumbColourId, juce::Colour(244, 185, 66));
    master.setColour(juce::Slider::thumbColourId, juce::Colour(85, 214, 190));
    deckGainA.setColour(juce::Slider::thumbColourId, juce::Colour(184, 243, 74));
    deckGainB.setColour(juce::Slider::thumbColourId, juce::Colour(255, 107, 94));

    const juce::Colour deckColours[] = {
        juce::Colour(184, 243, 74), juce::Colour(255, 107, 94)
    };
    for (int deck = 0; deck < 2; ++deck)
    {
        auto& button = headphoneButtons[deck];
        button.setButtonText(deck == 0 ? "HP A" : "HP B");
        button.setClickingTogglesState(true);
        button.setColour(juce::TextButton::buttonColourId, juce::Colour(41, 48, 45));
        button.setColour(juce::TextButton::buttonOnColourId, deckColours[deck].darker(0.38f));
        button.setTooltip(deck == 0 ? "Binaural headphones Deck A"
                                    : "Binaural headphones Deck B");
        button.onClick = [this, deck]{
            engine.setHeadphoneEnabled(deck, headphoneButtons[deck].getToggleState());
        };
        addAndMakeVisible(button);

        auto& volume = headphoneVolumes[deck];
        setupSlider(volume, 0.0, 1.0, 0.7, false);
        volume.setDoubleClickReturnValue(true, 0.7);
        volume.setColour(juce::Slider::thumbColourId, deckColours[deck]);
        volume.setTooltip(deck == 0 ? "Deck A headphone volume" : "Deck B headphone volume");
        volume.onValueChange = [this, deck]{
            engine.setHeadphoneVolume(deck, (float) headphoneVolumes[deck].getValue());
        };
        addAndMakeVisible(volume);
    }

    static constexpr const char* filterNames[] = { "LOW", "MID", "HIGH", "LP / HP" };
    for (int deck = 0; deck < 2; ++deck)
        for (int filter = 0; filter < 4; ++filter)
            setupDeckFilter(deck, filter, filterNames[filter],
                            filter == 3 ? -1.0 : -24.0,
                            filter == 3 ? 1.0 : 12.0, 0.0);

    deckFilters[0][0].onValueChange = [this]{ deckA.setLowEqDb((float) deckFilters[0][0].getValue()); };
    deckFilters[0][1].onValueChange = [this]{ deckA.setMidEqDb((float) deckFilters[0][1].getValue()); };
    deckFilters[0][2].onValueChange = [this]{ deckA.setHighEqDb((float) deckFilters[0][2].getValue()); };
    deckFilters[0][3].onValueChange = [this]{ deckA.setFilter((float) deckFilters[0][3].getValue()); };
    deckFilters[1][0].onValueChange = [this]{ deckB.setLowEqDb((float) deckFilters[1][0].getValue()); };
    deckFilters[1][1].onValueChange = [this]{ deckB.setMidEqDb((float) deckFilters[1][1].getValue()); };
    deckFilters[1][2].onValueChange = [this]{ deckB.setHighEqDb((float) deckFilters[1][2].getValue()); };
    deckFilters[1][3].onValueChange = [this]{ deckB.setFilter((float) deckFilters[1][3].getValue()); };

    for (auto* l : { &labelA, &labelB, &labelXf, &labelM })
    {
        l->setJustificationType(juce::Justification::centred);
        l->setColour(juce::Label::textColourId, juce::Colour(205, 214, 218));
        l->setFont(juce::Font(12.5f, juce::Font::bold));
        addAndMakeVisible(*l);
    }

    labelA.setColour(juce::Label::textColourId, juce::Colour(184, 243, 74));
    labelB.setColour(juce::Label::textColourId, juce::Colour(255, 107, 94));
    labelM.setColour(juce::Label::textColourId, juce::Colour(85, 214, 190));
    labelXf.setColour(juce::Label::textColourId, juce::Colour(244, 185, 66));

    addAndMakeVisible(crossfader);
    addAndMakeVisible(master);
    addAndMakeVisible(deckGainA);
    addAndMakeVisible(deckGainB);

    addAndMakeVisible(vuA);
    addAndMakeVisible(vuB);
    addAndMakeVisible(vuMaster);
    addAndMakeVisible(energyVisualizer);
    addAndMakeVisible(spatialMixerButton);
    spatialMixerButton.setColour(juce::TextButton::buttonColourId, juce::Colour(48, 153, 134));
    spatialMixerButton.onClick = std::move(openSpatialMixer);

    startTimerHz(20);
}

void MixerComponent::setCrossfaderNormalized(float value)
{
    crossfader.setValue(juce::jlimit(0.0f, 1.0f, value), juce::sendNotificationSync);
}

void MixerComponent::setMasterNormalized(float value)
{
    master.setValue(juce::jmap(juce::jlimit(0.0f, 1.0f, value), 0.0f, 2.0f),
                    juce::sendNotificationSync);
}

void MixerComponent::setDeckVolumeNormalized(int deckIndex, float value)
{
    if (deckIndex < 0 || deckIndex >= 2)
        return;

    auto& slider = deckIndex == 0 ? deckGainA : deckGainB;
    slider.setValue(juce::jmap(juce::jlimit(0.0f, 1.0f, value), 0.0f, 2.0f),
                    juce::sendNotificationSync);
}

void MixerComponent::setDeckTrimNormalized(int deckIndex, float value)
{
    engine.setDeckTrimGain(deckIndex,
                           juce::jmap(juce::jlimit(0.0f, 1.0f, value), 0.0f, 2.0f));
}

void MixerComponent::setDeckEqNormalized(int deckIndex, int bandIndex, float value)
{
    if (deckIndex < 0 || deckIndex >= 2 || bandIndex < 0 || bandIndex >= 3)
        return;

    deckFilters[deckIndex][bandIndex].setValue(
        juce::jmap(juce::jlimit(0.0f, 1.0f, value), -24.0f, 12.0f),
        juce::sendNotificationSync);
}

void MixerComponent::setDeckFilterNormalized(int deckIndex, float value)
{
    if (deckIndex < 0 || deckIndex >= 2)
        return;

    deckFilters[deckIndex][3].setValue(
        juce::jmap(juce::jlimit(0.0f, 1.0f, value), -1.0f, 1.0f),
        juce::sendNotificationSync);
}

void MixerComponent::toggleHeadphoneCue(int deckIndex)
{
    if (deckIndex < 0 || deckIndex >= 2)
        return;

    headphoneButtons[deckIndex].triggerClick();
}

bool MixerComponent::getHeadphoneCueEnabled(int deckIndex) const
{
    return deckIndex >= 0 && deckIndex < 2
        && headphoneButtons[deckIndex].getToggleState();
}

void MixerComponent::setupSlider(juce::Slider& s, double min, double max, double init, bool vertical)
{
    s.setRange(min, max, 0.01);
    s.setValue(init);
    s.setSliderStyle(vertical ? juce::Slider::LinearVertical : juce::Slider::LinearHorizontal);
    s.setTextBoxStyle(juce::Slider::NoTextBox, false, 0, 0);
    s.setLookAndFeel(&lnf);
}

void MixerComponent::setupDeckFilter(int deckIndex, int filterIndex, const juce::String& name,
                                     double min, double max, double initialValue)
{
    auto& slider = deckFilters[deckIndex][filterIndex];
    slider.setRange(min, max, filterIndex == 3 ? 0.01 : 0.1);
    slider.setValue(initialValue);
    slider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
    slider.setTextBoxStyle(juce::Slider::NoTextBox, false, 0, 0);
    slider.setDoubleClickReturnValue(true, 0.0);
    slider.setColour(juce::Slider::rotarySliderFillColourId,
                     deckIndex == 0 ? juce::Colour(184, 243, 74) : juce::Colour(255, 107, 94));
    slider.setColour(juce::Slider::rotarySliderOutlineColourId, juce::Colour(52, 61, 57));
    slider.setLookAndFeel(&lnf);
    addAndMakeVisible(slider);

    auto& label = deckFilterLabels[deckIndex][filterIndex];
    label.setText(name, juce::dontSendNotification);
    label.setJustificationType(juce::Justification::centred);
    label.setColour(juce::Label::textColourId, juce::Colour(157, 168, 163));
    label.setFont(juce::Font(9.5f, juce::Font::bold));
    addAndMakeVisible(label);
}

void MixerComponent::resized()
{
    auto area = getLocalBounds().reduced(16);
    spatialMixerButton.setBounds(area.removeFromTop(34));
    area.removeFromTop(14);

    auto masterArea = area.removeFromTop(138);
    labelM.setBounds(masterArea.removeFromTop(20));
    auto masterRow = masterArea.removeFromTop(44).reduced(8, 2);
    vuMaster.setBounds(masterRow.removeFromRight(14));
    masterRow.removeFromRight(8);
    master.setBounds(masterRow);

    masterArea.removeFromTop(4);
    for (int deck = 0; deck < 2; ++deck)
    {
        auto row = masterArea.removeFromTop(30);
        headphoneButtons[deck].setBounds(row.removeFromLeft(52));
        row.removeFromLeft(7);
        headphoneVolumes[deck].setBounds(row.reduced(2, 3));
        if (deck == 0)
            masterArea.removeFromTop(4);
    }

    area.removeFromTop(18);
    auto crossArea = area.removeFromBottom(66);
    area.removeFromBottom(12);
    energyVisualizer.setBounds(area.removeFromBottom(180));
    area.removeFromBottom(16);

    auto labels = area.removeFromTop(22);
    const int laneGap = 18;
    const int laneWidth = (labels.getWidth() - laneGap) / 2;
    labelA.setBounds(labels.removeFromLeft(laneWidth));
    labels.removeFromLeft(laneGap);
    labelB.setBounds(labels);

    area.removeFromTop(6);
    auto faders = area;
    auto laneA = faders.removeFromLeft(laneWidth);
    faders.removeFromLeft(laneGap);
    auto laneB = faders;

    auto placeDeckStrip = [this](juce::Rectangle<int> lane, int deckIndex,
                                 juce::Slider& slider, VUMeter& meter)
    {
        meter.setBounds(lane.removeFromRight(14).reduced(0, 5));
        lane.removeFromRight(4);
        slider.setBounds(lane.removeFromRight(30));
        lane.removeFromRight(4);

        const int controlHeight = lane.getHeight() / 4;
        for (int filter = 0; filter < 4; ++filter)
        {
            auto control = filter == 3 ? lane : lane.removeFromTop(controlHeight);
            deckFilterLabels[deckIndex][filter].setBounds(control.removeFromTop(13));
            deckFilters[deckIndex][filter].setBounds(control.reduced(2, 0));
        }
    };
    placeDeckStrip(laneA, 0, deckGainA, vuA);
    placeDeckStrip(laneB, 1, deckGainB, vuB);

    labelXf.setBounds(crossArea.removeFromTop(20));
    crossfader.setBounds(crossArea.reduced(6, 0));
}

void MixerComponent::paint(juce::Graphics& g)
{
    auto panel = getLocalBounds().toFloat().reduced(0.5f);
    g.setGradientFill(juce::ColourGradient(juce::Colour(27, 31, 29), 0.0f, 0.0f,
                                           juce::Colour(16, 19, 19), 0.0f, panel.getBottom(),
                                           false));
    g.fillRoundedRectangle(panel, 16.0f);
    g.setColour(juce::Colour(46, 54, 51));
    g.drawRoundedRectangle(panel, 16.0f, 1.0f);

    juce::ColourGradient accent(juce::Colour(184, 243, 74), 16.0f, 0.0f,
                                juce::Colour(255, 107, 94),
                                static_cast<float>(getWidth() - 16), 0.0f, false);
    accent.addColour(0.5, juce::Colour(85, 214, 190));
    g.setGradientFill(accent);
    g.fillRoundedRectangle(16.0f, 1.0f, getWidth() - 32.0f, 3.0f, 1.5f);

    g.setColour(juce::Colour(39, 46, 43));
    for (const int y : { labelA.getY() - 9, energyVisualizer.getY() - 8,
                         labelXf.getY() - 7 })
        g.drawHorizontalLine(y, 16.0f, static_cast<float>(getWidth() - 16));
}

void MixerComponent::timerCallback()
{
    float a = std::max(deckA.getRms(0), deckA.getRms(1));
    float b = std::max(deckB.getRms(0), deckB.getRms(1));
    float m = std::max(engine.getMasterRms(0), engine.getMasterRms(1));

    vuA.setLevel(a);
    vuB.setLevel(b);
    vuMaster.setLevel(m);
    energyVisualizer.repaint();
}