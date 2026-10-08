#include <JuceHeader.h>
#include "MainComponent.h"

//==============================================================================
// Applicazione JUCE
class LookaheadDJApplication : public juce::JUCEApplication,
                               private juce::MenuBarModel
{
public:
    const juce::String getApplicationName() override    { return "LookaheadDJ"; }
    const juce::String getApplicationVersion() override { return "0.1.0"; }
    bool moreThanOneInstanceAllowed() override          { return true; }

    void initialise (const juce::String&) override
    {
        mainWindow.reset (new MainWindow (getApplicationName()));

       #if JUCE_MAC
        juce::PopupMenu applicationMenu;
        applicationMenu.addItem (audioMidiSettingsMenuItem, "Audio & MIDI Settings...");
        juce::MenuBarModel::setMacMainMenu (this, &applicationMenu);
       #endif
    }

    void shutdown() override
    {
       #if JUCE_MAC
        juce::MenuBarModel::setMacMainMenu (nullptr);
       #endif
        mainWindow = nullptr;
    }

    void systemRequestedQuit() override
    {
        quit();
    }

    void anotherInstanceStarted (const juce::String&) override {}

private:
    enum
    {
        audioMidiSettingsMenuItem = 1001
    };

    juce::StringArray getMenuBarNames() override
    {
        return {};
    }

    juce::PopupMenu getMenuForIndex(int, const juce::String&) override
    {
        return {};
    }

    void menuItemSelected(int menuItemID, int) override
    {
        if (menuItemID == audioMidiSettingsMenuItem && mainWindow != nullptr)
            mainWindow->showAudioMidiSettings();
    }

    // Finestra principale
    class MainWindow : public juce::DocumentWindow
    {
    public:
        MainWindow (juce::String name)
        : DocumentWindow (name,
                          juce::Desktop::getInstance().getDefaultLookAndFeel()
                              .findColour (juce::ResizableWindow::backgroundColourId),
                          DocumentWindow::allButtons)
        {
            setUsingNativeTitleBar (true);
            setContentOwned (new MainComponent(), true);

           #if JUCE_IOS || JUCE_ANDROID
            setFullScreen (true);
           #else
            setResizable (true, true);
            setResizeLimits (1240, 780, 1920, 1200);
            centreWithSize (getWidth(), getHeight());
           #endif

            setVisible (true);
        }

        void showAudioMidiSettings()
        {
            if (auto* mainComponent = dynamic_cast<MainComponent*> (getContentComponent()))
                mainComponent->showAudioMidiSettings();
        }

        void closeButtonPressed() override
        {
            JUCEApplication::getInstance()->systemRequestedQuit();
        }

    private:
        JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (MainWindow)
    };

    std::unique_ptr<MainWindow> mainWindow;
};

//==============================================================================
// Entry point
START_JUCE_APPLICATION (LookaheadDJApplication)