#include "MainComponent.h"

namespace
{
    class AudioSettingsContent : public juce::Component,
                                 private juce::ChangeListener
    {
    public:
        explicit AudioSettingsContent(juce::AudioDeviceManager& deviceManager)
            : deviceManager(deviceManager),
              selector(deviceManager,
                       0, 2,
                       2, 64,
                       true, true,
                       false, false)
        {
            selector.setItemHeight(22);
            selector.setSize(454, 600);
            viewport.setViewedComponent(&selector, false);
            viewport.setScrollBarsShown(true, false);
            viewport.setScrollBarThickness(10);
            addAndMakeVisible(viewport);

            outputGroup.setText("Decoder Output");
            addAndMakeVisible(outputGroup);

            outputCountLabel.setText("Active outputs", juce::dontSendNotification);
            outputCountLabel.setJustificationType(juce::Justification::centredRight);
            addAndMakeVisible(outputCountLabel);

            outputCount.onChange = [this] { applyOutputCount(); };
            addAndMakeVisible(outputCount);

            appleAudioSetupButton.setButtonText("Open Apple Audio MIDI Setup");
            appleAudioSetupButton.onClick = [this] { openAppleAudioSetup(); };
            addAndMakeVisible(appleAudioSetupButton);

            statusLabel.setColour(juce::Label::textColourId, juce::Colours::orange);
            statusLabel.setJustificationType(juce::Justification::centred);
            addAndMakeVisible(statusLabel);

            deviceManager.addChangeListener(this);
            refreshOutputChoices();
            setSize(480, 520);
        }

        ~AudioSettingsContent() override
        {
            deviceManager.removeChangeListener(this);
        }

        void resized() override
        {
            auto bounds = getLocalBounds();
            auto outputBounds = bounds.removeFromBottom(108);
            viewport.setBounds(bounds);
            selector.setSize(juce::jmax(420, viewport.getMaximumVisibleWidth()),
                             selector.getHeight());

            outputGroup.setBounds(outputBounds.reduced(8, 2));
            auto controls = outputGroup.getBounds().reduced(12, 22);
            auto firstRow = controls.removeFromTop(26);
            outputCountLabel.setBounds(firstRow.removeFromLeft(130));
            outputCount.setBounds(firstRow.removeFromLeft(70));
            firstRow.removeFromLeft(10);
            appleAudioSetupButton.setBounds(firstRow);
            statusLabel.setBounds(controls.removeFromTop(24));
        }

    private:
        void changeListenerCallback(juce::ChangeBroadcaster*) override
        {
            refreshOutputChoices();
        }

        void refreshOutputChoices()
        {
            auto* device = deviceManager.getCurrentAudioDevice();
            const int availableOutputs = device != nullptr
                ? juce::jmin(64, device->getOutputChannelNames().size())
                : 0;
            const int activeOutputs = device != nullptr
                ? device->getActiveOutputChannels().countNumberOfSetBits()
                : 0;

            outputCount.clear(juce::dontSendNotification);
            const int firstChoice = availableOutputs == 1 ? 1 : 2;
            for (int channels = firstChoice; channels <= availableOutputs; ++channels)
                outputCount.addItem(juce::String(channels), channels);

            outputCount.setEnabled(availableOutputs > 0);
            outputCount.setSelectedId(activeOutputs, juce::dontSendNotification);
            if (activeOutputs > 0 && outputCount.getSelectedId() == 0)
                outputCount.setText(juce::String(activeOutputs), juce::dontSendNotification);
        }

        void applyOutputCount()
        {
            const int requestedOutputs = outputCount.getSelectedId();
            if (requestedOutputs <= 0)
                return;

            const auto previousSetup = deviceManager.getAudioDeviceSetup();
            auto setup = previousSetup;
            setup.useDefaultOutputChannels = false;
            setup.outputChannels.clear();
            setup.outputChannels.setRange(0, requestedOutputs, true);

            const auto error = deviceManager.setAudioDeviceSetup(setup, true);
            if (error.isNotEmpty())
            {
                deviceManager.setAudioDeviceSetup(previousSetup, true);
                statusLabel.setText(error, juce::dontSendNotification);
            }
            else
            {
                statusLabel.setText({}, juce::dontSendNotification);
            }
        }

        void openAppleAudioSetup()
        {
            const juce::File modernPath("/System/Applications/Utilities/Audio MIDI Setup.app");
            const juce::File legacyPath("/Applications/Utilities/Audio MIDI Setup.app");
            const auto appPath = modernPath.exists() ? modernPath : legacyPath;

            if (! appPath.exists() || ! juce::Process::openDocument(appPath.getFullPathName(), {}))
                statusLabel.setText("Unable to open Apple Audio MIDI Setup", juce::dontSendNotification);
            else
                statusLabel.setText({}, juce::dontSendNotification);
        }

        juce::AudioDeviceManager& deviceManager;
        juce::AudioDeviceSelectorComponent selector;
        juce::Viewport viewport;
        juce::GroupComponent outputGroup;
        juce::Label outputCountLabel;
        juce::ComboBox outputCount;
        juce::TextButton appleAudioSetupButton;
        juce::Label statusLabel;
    };

    class AudioSettingsWindow : public juce::DocumentWindow
    {
    public:
        AudioSettingsWindow(juce::AudioDeviceManager& deviceManager, juce::Component& owner)
            : juce::DocumentWindow("Audio & MIDI Settings",
                                   juce::Colour(18, 22, 20),
                                   juce::DocumentWindow::closeButton)
        {
            setUsingNativeTitleBar(true);
            setContentOwned(new AudioSettingsContent(deviceManager), true);
            setResizable(true, true);
            setResizeLimits(420, 420, 620, 700);
            centreAroundComponent(owner.getTopLevelComponent(), 480, 550);
        }

        void closeButtonPressed() override
        {
            setVisible(false);
        }
    };

    class SpatialMixerWindow : public juce::DocumentWindow
    {
    public:
        explicit SpatialMixerWindow(AudioEngine& engine)
            : juce::DocumentWindow("Spatial Mixer",
                                   juce::Colour(9, 11, 12),
                                   juce::DocumentWindow::allButtons)
        {
            setUsingNativeTitleBar(true);
            setContentOwned(new SpatialMixerComponent(engine), true);
            setResizable(true, true);
            setResizeLimits(820, 580, 1600, 1100);
            centreWithSize(1080, 720);
        }

        void closeButtonPressed() override
        {
            setVisible(false);
        }
    };
}

MainComponent::MainComponent()
{
    formatManager.registerBasicFormats();
    std::unique_ptr<juce::XmlElement> savedAudioSettings;
    const auto settingsFile = getAudioSettingsFile();
    if (settingsFile.existsAsFile())
        savedAudioSettings = juce::XmlDocument::parse(settingsFile);

    deviceManager.initialise(0, 2, savedAudioSettings.get(), true);

    if (savedAudioSettings == nullptr)
    {
        if (auto* device = deviceManager.getCurrentAudioDevice())
        {
            auto setup = deviceManager.getAudioDeviceSetup();
            setup.useDefaultOutputChannels = false;
            setup.outputChannels.clear();
            setup.outputChannels.setRange(0, device->getOutputChannelNames().size(), true);
            deviceManager.setAudioDeviceSetup(setup, true);
        }
    }

    juce::File modelFile = juce::File::getSpecialLocation(juce::File::userDesktopDirectory)
        .getChildFile("milkydj_cpiupiu/lookaheadDJ/Models/model.onnx");
    engine.setModelFile(modelFile);

    deckAComp = std::make_unique<DeckComponent>("Deck A", engine.getDeck(0), formatManager);
    deckBComp = std::make_unique<DeckComponent>("Deck B", engine.getDeck(1), formatManager);
    deckAComp->setSyncTarget(deckBComp.get());
    deckBComp->setSyncTarget(deckAComp.get());
    mixerComp = std::make_unique<MixerComponent>(
        engine, engine.getDeck(0), engine.getDeck(1), [this] { showSpatialMixer(); });
    browserComp = std::make_unique<BrowserComponent>(
        [this](const juce::File& f){ deckAComp->loadFile(f); },
        [this](const juce::File& f){ deckBComp->loadFile(f); }
    );

    waveformComp = std::make_unique<GlobalWaveformComponent>(*deckAComp, *deckBComp);

    addAndMakeVisible(logo);
    addAndMakeVisible(*waveformComp);
    addAndMakeVisible(*deckAComp);
    addAndMakeVisible(*deckBComp);
    addAndMakeVisible(*mixerComp);
    addAndMakeVisible(*browserComp);

    midiController = std::make_unique<HerculesInpulse200Midi>(
        deviceManager, *deckAComp, *deckBComp, *mixerComp, *browserComp);

    deviceManager.addAudioCallback(&engine);
    setSize(1440, 900);
}

MainComponent::~MainComponent()
{
    midiController.reset();
    deviceManager.removeAudioCallback(&engine);

    if (auto state = deviceManager.createStateXml())
    {
        const auto settingsFile = getAudioSettingsFile();
        settingsFile.getParentDirectory().createDirectory();
        settingsFile.replaceWithText(state->toString());
    }
}

juce::File MainComponent::getAudioSettingsFile() const
{
    return juce::File::getSpecialLocation(juce::File::userApplicationDataDirectory)
        .getChildFile("LookaheadDJ")
        .getChildFile("AudioMidiSettings.xml");
}

void MainComponent::showAudioMidiSettings()
{
    if (audioSettingsWindow == nullptr)
        audioSettingsWindow = std::make_unique<AudioSettingsWindow>(deviceManager, *this);

    audioSettingsWindow->setVisible(true);
    audioSettingsWindow->toFront(true);
}

void MainComponent::showSpatialMixer()
{
    if (spatialMixerWindow == nullptr)
        spatialMixerWindow = std::make_unique<SpatialMixerWindow>(engine);

    spatialMixerWindow->setVisible(true);
    spatialMixerWindow->toFront(true);
}

void MainComponent::paint(juce::Graphics& g)
{
    g.setGradientFill(juce::ColourGradient(juce::Colour(16, 20, 18), 0.0f, 0.0f,
                                           juce::Colour(9, 11, 12),
                                           static_cast<float>(getWidth()),
                                           static_cast<float>(getHeight()), false));
    g.fillAll();

    g.setColour(juce::Colour(12, 15, 15).withAlpha(0.82f));
    g.fillRect(0, 0, getWidth(), 62);
    g.setColour(juce::Colour(44, 51, 48));
    g.drawHorizontalLine(61, 14.0f, static_cast<float>(getWidth() - 14));

    const auto statusX = getWidth() - 132;
    g.setColour(juce::Colour(184, 243, 74));
    g.fillEllipse(static_cast<float>(statusX), 27.0f, 7.0f, 7.0f);
    g.setColour(juce::Colour(176, 184, 180));
    g.setFont(juce::Font(11.0f, juce::Font::bold));
    g.drawText("LIVE", statusX + 13, 20, 64, 20, juce::Justification::centredLeft);
}

void MainComponent::resized()
{
    constexpr int gap = 12;
    auto area = getLocalBounds().reduced(14);
    auto header = area.removeFromTop(40);
    logo.setBounds(header.removeFromLeft(220));
    area.removeFromTop(10);

    const int browserWidth = juce::jlimit(232, 270, area.getWidth() / 5);
    const int mixerWidth = juce::jlimit(258, 292, area.getWidth() / 5);

    browserComp->setBounds(area.removeFromLeft(browserWidth));
    area.removeFromLeft(gap);
    mixerComp->setBounds(area.removeFromRight(mixerWidth));
    area.removeFromRight(gap);

    const int waveformHeight = juce::jlimit(112, 146, area.getHeight() / 5);
    waveformComp->setBounds(area.removeFromTop(waveformHeight));
    area.removeFromTop(gap);

    auto deckA = area.removeFromLeft((area.getWidth() - gap) / 2);
    area.removeFromLeft(gap);
    deckAComp->setBounds(deckA);
    deckBComp->setBounds(area);
}