#include "BrowserComponent.h"

BrowserComponent::BrowserComponent(LoadFn loadA, LoadFn loadB)
    : browser(juce::FileBrowserComponent::openMode | juce::FileBrowserComponent::canSelectFiles,
              juce::File::getSpecialLocation(juce::File::userHomeDirectory),
              nullptr, nullptr),
      loadDeckA(std::move(loadA)),
      loadDeckB(std::move(loadB))
{
    setLookAndFeel(&lnf);

    title.setFont(juce::Font(15.0f, juce::Font::bold));
    title.setColour(juce::Label::textColourId, juce::Colour(184, 243, 74));
    title.setJustificationType(juce::Justification::centredLeft);
    addAndMakeVisible(title);

    addAndMakeVisible(browser);
    addAndMakeVisible(analyzeButton);
    addAndMakeVisible(loadAButton);
    addAndMakeVisible(loadBButton);

    styleButton(analyzeButton, juce::Colour(59, 68, 64));
    styleButton(loadAButton, juce::Colour(130, 180, 49));
    styleButton(loadBButton, juce::Colour(222, 84, 74));

    loadAButton.onClick = [this]{
        auto f = browser.getSelectedFile(0);
        if (f.existsAsFile() && loadDeckA) loadDeckA(f);
    };
    loadBButton.onClick = [this]{
        auto f = browser.getSelectedFile(0);
        if (f.existsAsFile() && loadDeckB) loadDeckB(f);
    };
    analyzeButton.onClick = [this]{ analyzeSelectedFile(); };
}

BrowserComponent::~BrowserComponent()
{
    analysisThread.reset();
    setLookAndFeel(nullptr);
}

void BrowserComponent::moveSelection(int delta)
{
    const juce::KeyPress key(delta < 0 ? juce::KeyPress::upKey : juce::KeyPress::downKey);
    for (int step = 0; step < std::abs(delta); ++step)
        browser.keyPressed(key);
}

void BrowserComponent::focusBrowser()
{
    browser.grabKeyboardFocus();
}

void BrowserComponent::analyzeSelection()
{
    analyzeSelectedFile();
}

void BrowserComponent::loadSelectedIntoDeck(int deckIndex)
{
    const auto file = browser.getSelectedFile(0);
    if (!file.existsAsFile())
        return;

    auto& callback = deckIndex == 0 ? loadDeckA : loadDeckB;
    if (callback)
        callback(file);
}

void BrowserComponent::analyzeSelectedFile()
{
    auto file = browser.getSelectedFile(0);
    if (! file.existsAsFile())
    {
        title.setText("SELECT A FILE", juce::dontSendNotification);
        return;
    }

    analysisThread.reset();
    analyzedFile = file;
    analyzeButton.setEnabled(false);
    analyzeButton.setButtonText("ANALYZING...");
    title.setText(file.getFileNameWithoutExtension(), juce::dontSendNotification);

    juce::Component::SafePointer<BrowserComponent> safeThis(this);
    analysisThread = std::make_unique<BpmAnalysisThread>(
        file,
        [safeThis, file](BpmAnalysisResult result) mutable
        {
            if (safeThis != nullptr)
                safeThis->finishAnalysis(file, std::move(result));
        });
    analysisThread->start();
}

void BrowserComponent::finishAnalysis(const juce::File& file, BpmAnalysisResult result)
{
    if (file != analyzedFile)
        return;

    analyzeButton.setEnabled(true);
    analyzeButton.setButtonText("ANALYZE");

    const auto status = result.error.isNotEmpty() || result.bpm <= 0.0
        ? "ANALYSIS FAILED"
        : file.getFileNameWithoutExtension() + " | " + juce::String(result.bpm, 1) + " BPM";
    title.setText(status, juce::dontSendNotification);
    analysisThread.reset();
}

void BrowserComponent::styleButton(juce::TextButton& b, juce::Colour bg)
{
    b.setColour(juce::TextButton::buttonColourId, bg);
    b.setColour(juce::TextButton::buttonOnColourId, bg.brighter(0.12f));
    b.setColour(juce::TextButton::textColourOffId, juce::Colours::white);
    b.setColour(juce::TextButton::textColourOnId, juce::Colours::white);
}

void BrowserComponent::resized()
{
    auto area = getLocalBounds().reduced(14);
    title.setBounds(area.removeFromTop(30));
    area.removeFromTop(8);

    auto actions = area.removeFromBottom(78);
    analyzeButton.setBounds(actions.removeFromBottom(32));
    actions.removeFromBottom(8);
    auto loadRow = actions.removeFromBottom(34);
    loadAButton.setBounds(loadRow.removeFromLeft((loadRow.getWidth() - 8) / 2));
    loadRow.removeFromLeft(8);
    loadBButton.setBounds(loadRow);

    area.removeFromBottom(10);
    browser.setBounds(area);
}

void BrowserComponent::paint(juce::Graphics& g)
{
    auto panel = getLocalBounds().toFloat().reduced(0.5f);
    g.setGradientFill(juce::ColourGradient(juce::Colour(25, 29, 27), 0.0f, 0.0f,
                                           juce::Colour(14, 17, 17), 0.0f, panel.getBottom(),
                                           false));
    g.fillRoundedRectangle(panel, 16.0f);
    g.setColour(juce::Colour(46, 54, 51));
    g.drawRoundedRectangle(panel, 16.0f, 1.0f);

    g.setColour(juce::Colour(184, 243, 74));
    g.fillRoundedRectangle(14.0f, 1.0f, getWidth() - 28.0f, 3.0f, 1.5f);
}