#pragma once
#include <JuceHeader.h>
#include "DJLookAndFeel.h"
#include "BpmAnalyzer.h"

class BrowserComponent : public juce::Component
{
public:
    using LoadFn = std::function<void(const juce::File&)>;

    BrowserComponent(LoadFn loadA, LoadFn loadB);
    ~BrowserComponent() override;

    void resized() override;
    void paint(juce::Graphics&) override;

    void moveSelection(int delta);
    void focusBrowser();
    void analyzeSelection();
    void loadSelectedIntoDeck(int deckIndex);

private:
    void styleButton(juce::TextButton& b, juce::Colour bg);
    void analyzeSelectedFile();
    void finishAnalysis(const juce::File& file, BpmAnalysisResult result);

    DJLookAndFeel lnf;

    juce::Label title { "BrowserTitle", "LIBRARY" };
    juce::FileBrowserComponent browser;

    juce::TextButton analyzeButton { "ANALYZE" };
    juce::TextButton loadAButton { "LOAD A" };
    juce::TextButton loadBButton { "LOAD B" };

    LoadFn loadDeckA;
    LoadFn loadDeckB;
    std::unique_ptr<BpmAnalysisThread> analysisThread;
    juce::File analyzedFile;
};