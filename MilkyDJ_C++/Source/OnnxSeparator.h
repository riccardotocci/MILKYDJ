#pragma once
#include <JuceHeader.h>
#include <onnxruntime_cxx_api.h>

class OnnxSeparator
{
public:
    static constexpr int64_t DEMUCS_WINDOW = 343980;

    OnnxSeparator() = default;

    bool loadModel(const juce::File& modelFile)
    {
        if (!modelFile.existsAsFile())
            return false;

        Ort::SessionOptions opts;
        
        // Limita i thread per lasciare CPU al resto dell'app
        opts.SetIntraOpNumThreads(6);
        opts.SetInterOpNumThreads(1);
        opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        
        // Disabilita spinning per ridurre uso CPU idle
        opts.AddConfigEntry("session.intra_op.allow_spinning", "0");

        try {
            std::string modelPath = modelFile.getFullPathName().toStdString();
            session.reset(new Ort::Session(env, modelPath.c_str(), opts));

            inputName = session->GetInputNameAllocated(0, allocator);
            outputName = session->GetOutputNameAllocated(0, allocator);

            inputBuffer.resize(static_cast<size_t>(2 * DEMUCS_WINDOW), 0.0f);

            DBG("ONNX Model loaded (6 threads, optimized)");
        } catch (const Ort::Exception& e) {
            DBG("ONNX load error: " << e.what());
            session.reset();
            return false;
        }
        return true;
    }

    bool isLoaded() const { return session != nullptr; }
    int64_t getRequiredSamples() const { return DEMUCS_WINDOW; }

    bool processBlock(const float* const* in, int numChannels, int numSamples,
                      std::array<std::vector<float>, 4>& out)
    {
        if (numChannels < 2 || session == nullptr)
            return false;

        int samplesToCopy = std::min(numSamples, static_cast<int>(DEMUCS_WINDOW));
        std::fill(inputBuffer.begin(), inputBuffer.end(), 0.0f);
        for (int i = 0; i < samplesToCopy; ++i) {
            inputBuffer[static_cast<size_t>(i)] = in[0][i];
            inputBuffer[static_cast<size_t>(DEMUCS_WINDOW + i)] = in[1][i];
        }

        std::array<int64_t, 3> inputShape { 1, 2, DEMUCS_WINDOW };
        Ort::MemoryInfo memInfo = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        Ort::Value inputTensor = Ort::Value::CreateTensor<float>(
            memInfo, inputBuffer.data(), inputBuffer.size(), inputShape.data(), inputShape.size());

        const char* inputNames[] = { inputName.get() };
        const char* outputNames[] = { outputName.get() };

        try {
            auto outputs = session->Run(
                Ort::RunOptions{ nullptr },
                inputNames, &inputTensor, 1,
                outputNames, 1);

            auto& outputTensor = outputs[0];
            float* outputData = outputTensor.GetTensorMutableData<float>();

            int64_t T = DEMUCS_WINDOW;

            for (int stem = 0; stem < 4; ++stem) {
                auto& v = out[stem];
                v.resize(static_cast<size_t>(T * 2));

                const float* srcL = outputData + stem * 2 * T;
                const float* srcR = srcL + T;

                for (int64_t i = 0; i < T; ++i) {
                    v[static_cast<size_t>(i * 2)]     = srcL[i];
                    v[static_cast<size_t>(i * 2 + 1)] = srcR[i];
                }
            }

        } catch (const Ort::Exception& e) {
            DBG("ONNX run error: " << e.what());
            return false;
        }

        return true;
    }

private:
    Ort::Env env { ORT_LOGGING_LEVEL_WARNING, "LookaheadDJ" };
    Ort::AllocatorWithDefaultOptions allocator;
    std::unique_ptr<Ort::Session> session;

    Ort::AllocatedStringPtr inputName { nullptr, Ort::detail::AllocatedFree{nullptr} };
    Ort::AllocatedStringPtr outputName { nullptr, Ort::detail::AllocatedFree{nullptr} };

    std::vector<float> inputBuffer;
};