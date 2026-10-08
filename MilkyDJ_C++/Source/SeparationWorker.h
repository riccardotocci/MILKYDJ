#pragma once
#include <JuceHeader.h>
#include "LookaheadBuffer.h"
#include "OnnxSeparator.h"

#pragma once
#include <JuceHeader.h>
#include "LookaheadBuffer.h"
#include "OnnxSeparator.h"

class SeparationWorker : private juce::Thread
{
public:
    SeparationWorker(LookaheadBuffer& inBuf,
                     std::array<std::unique_ptr<LookaheadBuffer>,4>& stemBuffers,
                     int block)
        : Thread("SeparationWorker"),
          input(inBuf),
          stems(stemBuffers),
          blockSize(block)
    {
    }

    void setModel(const juce::File& modelFile)
    {
        modelLoaded = separator.loadModel(modelFile);
        if (modelLoaded) {
            windowSize = static_cast<int>(separator.getRequiredSamples());
            DBG("Model loaded, window size: " << windowSize);
        } else {
            DBG("ERROR: Model failed to load!");
        }
    }

    void start() { startThread(); }
    void stop()  { signalThreadShouldExit(); stopThread(5000); }

    int64_t getProcessedSamples() const { return processedSamples.load(); }

private:
    void run() override
    {
        const int actualWindow = modelLoaded ? windowSize : 4096;
        const int overlapSamples = modelLoaded ? actualWindow / 4 : 0;
        const int hopSamples = actualWindow - overlapSamples;
        
        std::vector<float> tempL(static_cast<size_t>(actualWindow), 0.0f);
        std::vector<float> tempR(static_cast<size_t>(actualWindow), 0.0f);
        std::vector<float*> tempPtrs(2);

        std::vector<float> planarL(static_cast<size_t>(hopSamples), 0.0f);
        std::vector<float> planarR(static_cast<size_t>(hopSamples), 0.0f);
        std::vector<const float*> planarPtrs = { planarL.data(), planarR.data() };

        std::array<std::vector<float>, 4> stemBlock;
        std::array<std::vector<float>, 4> previousStemTails;
        for (auto& tail : previousStemTails)
            tail.resize(static_cast<size_t>(overlapSamples * 2), 0.0f);
        bool havePreviousWindow = false;

        while (! threadShouldExit())
        {
            const int inputSamplesNeeded = havePreviousWindow ? hopSamples : actualWindow;
            if (input.getAvailable() < inputSamplesNeeded) { wait(10); continue; }

            int minFree = std::numeric_limits<int>::max();
            for (int s = 0; s < 4; ++s)
                if (stems[s])
                    minFree = std::min(minFree, stems[s]->getFreeSpace());
            if (minFree < hopSamples) { wait(5); continue; }

            if (havePreviousWindow && overlapSamples > 0)
            {
                std::move(tempL.end() - overlapSamples, tempL.end(), tempL.begin());
                std::move(tempR.end() - overlapSamples, tempR.end(), tempR.begin());
            }

            const int inputOffset = havePreviousWindow ? overlapSamples : 0;
            tempPtrs[0] = tempL.data() + inputOffset;
            tempPtrs[1] = tempR.data() + inputOffset;
            const int n = input.pop(tempPtrs.data(), inputSamplesNeeded);
            if (n != inputSamplesNeeded)
            {
                havePreviousWindow = false;
                continue;
            }

            bool ok = false;
            
            if (modelLoaded) {
                ok = separator.processBlock(
                    const_cast<const float* const*>(std::array<float*, 2> {
                        tempL.data(), tempR.data()
                    }.data()), 2, actualWindow, stemBlock);
            } else {
                for (int stem = 0; stem < 4; ++stem) {
                    stemBlock[stem].resize(static_cast<size_t>(actualWindow * 2));
                    for (int i = 0; i < actualWindow; ++i) {
                        stemBlock[stem][static_cast<size_t>(i * 2)]     = tempL[static_cast<size_t>(i)];
                        stemBlock[stem][static_cast<size_t>(i * 2 + 1)] = tempR[static_cast<size_t>(i)];
                    }
                }
                ok = true;
            }

            if (! ok) continue;

            processedSamples.fetch_add(hopSamples, std::memory_order_relaxed);
            
            for (int stem = 0; stem < 4; ++stem)
            {
                auto& block = stemBlock[stem];
                if (block.size() < static_cast<size_t>(actualWindow * 2))
                    continue;

                for (int i = 0; i < hopSamples; ++i)
                {
                    float left = block[static_cast<size_t>(i * 2)];
                    float right = block[static_cast<size_t>(i * 2 + 1)];
                    if (havePreviousWindow && i < overlapSamples)
                    {
                        const auto fadeIn = static_cast<float>(i + 1)
                            / static_cast<float>(overlapSamples + 1);
                        const auto fadeOut = 1.0f - fadeIn;
                        const auto& tail = previousStemTails[static_cast<size_t>(stem)];
                        left = tail[static_cast<size_t>(i * 2)] * fadeOut + left * fadeIn;
                        right = tail[static_cast<size_t>(i * 2 + 1)] * fadeOut + right * fadeIn;
                    }
                    planarL[static_cast<size_t>(i)] = left;
                    planarR[static_cast<size_t>(i)] = right;
                }

                planarPtrs[0] = planarL.data();
                planarPtrs[1] = planarR.data();
                stems[stem]->push(planarPtrs.data(), hopSamples);

                auto& tail = previousStemTails[static_cast<size_t>(stem)];
                std::copy(block.begin() + static_cast<ptrdiff_t>(hopSamples * 2),
                          block.end(), tail.begin());
            }

            havePreviousWindow = true;
        }
    }

    LookaheadBuffer& input;
    std::array<std::unique_ptr<LookaheadBuffer>, 4>& stems;
    int blockSize;
    int windowSize = 4096;
    bool modelLoaded = false;
    OnnxSeparator separator;
    std::atomic<int64_t> processedSamples { 0 };
};