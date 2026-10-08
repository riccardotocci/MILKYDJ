#pragma once
#include <juce_audio_formats/juce_audio_formats.h>
#include "LookaheadBuffer.h"

class TrackDecoder : private juce::Thread
{
public:
    TrackDecoder(juce::AudioFormatManager& fm, LookaheadBuffer& inBuf, int numCh, int chunk = 8192)
        : Thread("TrackDecoder"), formatManager(fm), inputBuffer(inBuf), channels(numCh), chunkSize(chunk) {}

    ~TrackDecoder() override { stopAndClear(); }

    void loadAndStart(const juce::File& file, double targetSampleRate = 44100.0)
    {
        lastFile = file;
        lastTargetSampleRate = targetSampleRate;

        stopAndClear();
        reader.reset(formatManager.createReaderFor(file));
        if (reader == nullptr)
            return;

        position = 0;
        sourceSampleRate = reader->sampleRate;
        this->targetSampleRate = targetSampleRate;

        needsResampling = std::abs(sourceSampleRate - targetSampleRate) > 1.0;
        if (needsResampling)
        {
            resampleRatio = sourceSampleRate / targetSampleRate;
            totalSamplesTarget = static_cast<int64_t>(reader->lengthInSamples / resampleRatio);
        }
        else
        {
            totalSamplesTarget = reader->lengthInSamples;
        }

        startThread();
    }

    void seekToSamples(int64_t targetSamples)
    {
        if (lastFile == juce::File{})
            return;

        stopAndClear();

        reader.reset(formatManager.createReaderFor(lastFile));
        if (reader == nullptr)
            return;

        position = static_cast<int64_t>(targetSamples * resampleRatio);
        sourceSampleRate = reader->sampleRate;
        this->targetSampleRate = lastTargetSampleRate;

        needsResampling = std::abs(sourceSampleRate - targetSampleRate) > 1.0;
        if (needsResampling)
            resampleRatio = sourceSampleRate / targetSampleRate;
        else
            resampleRatio = 1.0;

        inputBuffer.clear();
        for (auto& r : resamplers)
            if (r) r->reset();

        startThread();
    }

    void stopAndClear()
    {
        signalThreadShouldExit();
        stopThread(2000);
        reader.reset();
        for (auto& r : resamplers)
            r.reset();
    }
    
    int64_t getTotalSamplesTarget() const { return totalSamplesTarget; }

private:
    void run() override
    {
        if (needsResampling)
            runWithResampling();
        else
            runDirect();
    }
    
    void runDirect()
    {
        juce::AudioBuffer<float> tempBuffer(channels, chunkSize);

        while (! threadShouldExit() && reader != nullptr)
        {
            juce::int64 remaining = reader->lengthInSamples - position;
            if (remaining <= 0)
                break;

            int samplesToRead = static_cast<int>(juce::jmin<juce::int64>(chunkSize, remaining));

            reader->read(&tempBuffer, 0, samplesToRead, position, true, true);
            position += samplesToRead;

            while (! threadShouldExit() && inputBuffer.getFreeSpace() < samplesToRead)
                wait(2);

            inputBuffer.push(tempBuffer.getArrayOfReadPointers(), samplesToRead);
        }
    }
    
    void runWithResampling()
    {
        int sourceChunkSize = static_cast<int>(std::ceil(chunkSize * resampleRatio)) + 16;
        
        juce::AudioBuffer<float> sourceBuffer(channels, sourceChunkSize);
        juce::AudioBuffer<float> destBuffer(channels, chunkSize);

        while (! threadShouldExit() && reader != nullptr)
        {
            juce::int64 remaining = reader->lengthInSamples - position;
            if (remaining <= 0)
                break;

            int sourceSamplesToRead = static_cast<int>(juce::jmin<juce::int64>(sourceChunkSize, remaining));

            sourceBuffer.clear();
            reader->read(&sourceBuffer, 0, sourceSamplesToRead, position, true, true);
            position += sourceSamplesToRead;

            int outputSamplesGenerated = 0;
            
            for (int ch = 0; ch < channels; ++ch)
            {
                if (!resamplers[ch])
                    resamplers[ch] = std::make_unique<juce::LagrangeInterpolator>();

                int samplesUsed = resamplers[ch]->process(
                    resampleRatio,
                    sourceBuffer.getReadPointer(ch),
                    destBuffer.getWritePointer(ch),
                    chunkSize,
                    sourceSamplesToRead,
                    false);
                
                juce::ignoreUnused(samplesUsed);
                outputSamplesGenerated = chunkSize;
            }

            if (remaining < sourceChunkSize)
            {
                outputSamplesGenerated = static_cast<int>(remaining / resampleRatio);
                if (outputSamplesGenerated <= 0)
                    break;
            }

            while (! threadShouldExit() && inputBuffer.getFreeSpace() < outputSamplesGenerated)
                wait(2);

            inputBuffer.push(destBuffer.getArrayOfReadPointers(), outputSamplesGenerated);
        }
    }

    juce::AudioFormatManager& formatManager;
    LookaheadBuffer& inputBuffer;
    int channels;
    int chunkSize;
    std::unique_ptr<juce::AudioFormatReader> reader;
    juce::int64 position { 0 };
    
    double sourceSampleRate { 44100.0 };
    double targetSampleRate { 44100.0 };
    double resampleRatio { 1.0 };
    bool needsResampling { false };
    std::array<std::unique_ptr<juce::LagrangeInterpolator>, 2> resamplers;
    
    int64_t totalSamplesTarget { 0 };

    juce::File lastFile;
    double lastTargetSampleRate { 44100.0 };
};