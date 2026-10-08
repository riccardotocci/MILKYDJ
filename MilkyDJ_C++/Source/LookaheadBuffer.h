#pragma once
#include <juce_audio_basics/juce_audio_basics.h>

class LookaheadBuffer {
public:
    LookaheadBuffer(int numChannels, int capacitySamples)
      : channels(numChannels),
        fifo(capacitySamples),
        buffers(static_cast<size_t>(numChannels))
    {
        for (auto& b : buffers)
            b.setSize(1, capacitySamples);
    }

    void push(const float* const* input, int numSamples) {
        int start1, size1, start2, size2;
        fifo.prepareToWrite(numSamples, start1, size1, start2, size2);
        if (size1 > 0) copy(input, start1, size1, 0);
        if (size2 > 0) copy(input, start2, size2, size1);
        fifo.finishedWrite(size1 + size2);
    }

    int pop(float* const* output, int maxSamples) {
        int start1, size1, start2, size2;
        fifo.prepareToRead(maxSamples, start1, size1, start2, size2);
        int total = size1 + size2;
        if (size1 > 0) copyOut(output, start1, size1, 0);
        if (size2 > 0) copyOut(output, start2, size2, size1);
        fifo.finishedRead(total);
        return total;
    }

    int getAvailable() const { return fifo.getNumReady(); }
    int getFreeSpace() const { return fifo.getFreeSpace(); }

    void clear() {
        fifo.reset();
        for (auto& b : buffers)
            b.clear();
    }

private:
    void copy(const float* const* in, int start, int size, int offset) {
        for (int ch = 0; ch < channels; ++ch)
            buffers[static_cast<size_t>(ch)].copyFrom(0, start, in[ch] + offset, size);
    }

    void copyOut(float* const* out, int start, int size, int offset) {
        for (int ch = 0; ch < channels; ++ch)
            juce::FloatVectorOperations::copy(out[ch] + offset,
                                              buffers[static_cast<size_t>(ch)].getReadPointer(0, start),
                                              size);
    }

    int channels;
    juce::AbstractFifo fifo;
    std::vector<juce::AudioBuffer<float>> buffers;
};