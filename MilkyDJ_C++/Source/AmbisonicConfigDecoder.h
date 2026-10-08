#pragma once

#include <JuceHeader.h>
#include <memory>
#include <vector>

class AmbisonicConfigDecoder
{
public:
    AmbisonicConfigDecoder();

    juce::Result loadConfiguration(const juce::File& file);
    void process(const juce::AudioBuffer<float>& ambisonicInput,
                 float* const* outputChannels,
                 int numOutputChannels,
                 int numSamples) const;

    juce::String getConfigurationName() const;
    juce::String getConfigurationPath() const;
    int getConfiguredOutputChannels() const;
    int getConfiguredOrder() const;

private:
    struct Configuration
    {
        juce::String name;
        juce::String path;
        int rows = 0;
        int columns = 0;
        int order = 0;
        int outputChannels = 0;
        bool expectsSn3d = true;
        std::vector<float> matrix;
        std::vector<int> routing;
    };

    static std::shared_ptr<Configuration> createDefaultConfiguration();
    static juce::Result parseConfiguration(const juce::File& file,
                                           std::shared_ptr<Configuration>& destination);

    mutable juce::SpinLock configurationLock;
    std::shared_ptr<const Configuration> configuration;
};
