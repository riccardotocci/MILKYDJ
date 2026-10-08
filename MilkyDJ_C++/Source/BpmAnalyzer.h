#pragma once

#include <JuceHeader.h>
#include <aubio/aubio.h>

struct BpmAnalysisResult
{
    double bpm { 0.0 };
    std::vector<double> beatTimes;
    juce::String error;
};

inline BpmAnalysisResult analyzeBpmFile(const juce::File& file,
                                        const std::function<bool()>& shouldCancel)
{
    BpmAnalysisResult result;
    constexpr uint_t hopSize = 512;
    constexpr uint_t winSize = 1024;
    uint_t sampleRate = 0;

    auto* source = new_aubio_source(file.getFullPathName().toRawUTF8(), sampleRate, hopSize);
    if (source == nullptr)
    {
        result.error = "Unable to open audio file";
        return result;
    }

    sampleRate = aubio_source_get_samplerate(source);
    auto* tempo = new_aubio_tempo("default", winSize, hopSize, sampleRate);
    auto* input = new_fvec(hopSize);
    auto* output = new_fvec(2);

    uint_t samplesRead = 0;
    do
    {
        if (shouldCancel())
            break;

        aubio_source_do(source, input, &samplesRead);
        aubio_tempo_do(tempo, input, output);

        if (output->data[0] != 0.0f)
            result.beatTimes.push_back(aubio_tempo_get_last_s(tempo));
    }
    while (samplesRead == hopSize);

    if (! shouldCancel())
        result.bpm = aubio_tempo_get_bpm(tempo);

    del_fvec(input);
    del_fvec(output);
    del_aubio_tempo(tempo);
    del_aubio_source(source);
    return result;
}

class BpmAnalysisThread : private juce::Thread
{
public:
    using Completion = std::function<void(BpmAnalysisResult)>;

    BpmAnalysisThread(juce::File fileToAnalyze, Completion completionCallback)
        : Thread("BPM Analysis"),
          file(std::move(fileToAnalyze)),
          completion(std::move(completionCallback))
    {
    }

    ~BpmAnalysisThread() override
    {
        cancel();
    }

    void start()
    {
        startThread();
    }

    void cancel()
    {
        signalThreadShouldExit();
        stopThread(5000);
    }

private:
    void run() override
    {
        auto result = analyzeBpmFile(file, [this] { return threadShouldExit(); });
        if (threadShouldExit())
            return;

        juce::MessageManager::callAsync(
            [callback = completion, analysisResult = std::move(result)]() mutable
            {
                callback(std::move(analysisResult));
            });
    }

    juce::File file;
    Completion completion;
};