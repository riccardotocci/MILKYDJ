#include "AmbisonicConfigDecoder.h"

#include <cmath>

AmbisonicConfigDecoder::AmbisonicConfigDecoder()
    : configuration(createDefaultConfiguration())
{
}

std::shared_ptr<AmbisonicConfigDecoder::Configuration>
AmbisonicConfigDecoder::createDefaultConfiguration()
{
    auto result = std::make_shared<Configuration>();
    result->name = "Stereo preview";
    result->rows = 2;
    result->columns = 64;
    result->order = 7;
    result->outputChannels = 2;
    result->matrix.assign(128, 0.0f);
    result->routing = { 0, 1 };

    result->matrix[0] = 0.70710678f;
    result->matrix[1] = 0.5f;
    result->matrix[64] = 0.70710678f;
    result->matrix[65] = -0.5f;
    return result;
}

juce::Result AmbisonicConfigDecoder::parseConfiguration(
    const juce::File& file,
    std::shared_ptr<Configuration>& destination)
{
    if (! file.existsAsFile())
        return juce::Result::fail("Config file not found");

    juce::var root;
    auto parseResult = juce::JSON::parse(file.loadFileAsString(), root);
    if (parseResult.failed())
        return juce::Result::fail(parseResult.getErrorMessage());
    if (! root.isObject() || ! root.hasProperty("Decoder"))
        return juce::Result::fail("No Decoder object found in the config");

    auto decoder = root.getProperty("Decoder", {});
    if (! decoder.isObject() || ! decoder.hasProperty("Matrix"))
        return juce::Result::fail("Decoder.Matrix is missing");

    auto matrix = decoder.getProperty("Matrix", {});
    auto* matrixRows = matrix.getArray();
    if (matrixRows == nullptr || matrixRows->isEmpty())
        return juce::Result::fail("Decoder.Matrix must contain at least one row");

    auto* firstRow = matrixRows->getReference(0).getArray();
    if (firstRow == nullptr || firstRow->isEmpty())
        return juce::Result::fail("Decoder.Matrix rows must not be empty");

    const int rows = matrixRows->size();
    const int columns = firstRow->size();
    const int order = static_cast<int>(std::sqrt(static_cast<double>(columns))) - 1;
    if (columns > 64 || columns != (order + 1) * (order + 1))
        return juce::Result::fail("Decoder matrix columns must equal (order + 1)^2 and be at most 64");

    auto parsed = std::make_shared<Configuration>();
    parsed->name = decoder.getProperty("Name", root.getProperty("Name", "Decoder")).toString();
    parsed->path = file.getFullPathName();
    parsed->rows = rows;
    parsed->columns = columns;
    parsed->order = order;
    parsed->matrix.resize(static_cast<size_t>(rows * columns));
    parsed->routing.resize(static_cast<size_t>(rows));

    for (int row = 0; row < rows; ++row)
    {
        auto* values = matrixRows->getReference(row).getArray();
        if (values == nullptr || values->size() != columns)
            return juce::Result::fail("All decoder matrix rows must have the same length");

        for (int column = 0; column < columns; ++column)
        {
            const auto& value = values->getReference(column);
            if (! value.isInt() && ! value.isInt64() && ! value.isDouble())
                return juce::Result::fail("Decoder matrix contains a non-numeric value");
            parsed->matrix[static_cast<size_t>(row * columns + column)] = static_cast<float>(value);
        }
        parsed->routing[static_cast<size_t>(row)] = row;
    }

    if (decoder.hasProperty("Routing"))
    {
        auto* routing = decoder.getProperty("Routing", {}).getArray();
        if (routing == nullptr || routing->size() != rows)
            return juce::Result::fail("Decoder.Routing length must match the matrix row count");

        for (int row = 0; row < rows; ++row)
        {
            const auto& route = routing->getReference(row);
            if (! route.isInt() && ! route.isInt64())
                return juce::Result::fail("Decoder.Routing values must be integers");
            parsed->routing[static_cast<size_t>(row)] = static_cast<int>(route) - 1;
        }
    }

    parsed->outputChannels = 0;
    for (const auto route : parsed->routing)
    {
        if (route < 0 || route >= 64)
            return juce::Result::fail("Decoder.Routing values must be between 1 and 64");
        parsed->outputChannels = juce::jmax(parsed->outputChannels, route + 1);
    }

    const auto normalization = decoder.getProperty("ExpectedInputNormalization", "sn3d").toString();
    if (! normalization.equalsIgnoreCase("sn3d") && ! normalization.equalsIgnoreCase("n3d"))
        return juce::Result::fail("ExpectedInputNormalization must be SN3D or N3D");
    parsed->expectsSn3d = normalization.equalsIgnoreCase("sn3d");

    destination = std::move(parsed);
    return juce::Result::ok();
}

juce::Result AmbisonicConfigDecoder::loadConfiguration(const juce::File& file)
{
    std::shared_ptr<Configuration> parsed;
    auto result = parseConfiguration(file, parsed);
    if (result.failed())
        return result;

    const juce::SpinLock::ScopedLockType lock(configurationLock);
    configuration = std::move(parsed);
    return juce::Result::ok();
}

void AmbisonicConfigDecoder::process(const juce::AudioBuffer<float>& ambisonicInput,
                                     float* const* outputChannels,
                                     int numOutputChannels,
                                     int numSamples) const
{
    for (int channel = 0; channel < numOutputChannels; ++channel)
        juce::FloatVectorOperations::clear(outputChannels[channel], numSamples);

    std::shared_ptr<const Configuration> activeConfiguration;
    {
        const juce::SpinLock::ScopedLockType lock(configurationLock);
        activeConfiguration = configuration;
    }

    if (activeConfiguration == nullptr)
        return;

    const int inputChannels = juce::jmin(activeConfiguration->columns,
                                         ambisonicInput.getNumChannels());
    for (int row = 0; row < activeConfiguration->rows; ++row)
    {
        const int destination = activeConfiguration->routing[static_cast<size_t>(row)];
        if (destination < 0 || destination >= numOutputChannels)
            continue;

        for (int channel = 0; channel < inputChannels; ++channel)
        {
            float coefficient = activeConfiguration->matrix[
                static_cast<size_t>(row * activeConfiguration->columns + channel)];
            if (! activeConfiguration->expectsSn3d)
            {
                const int degree = static_cast<int>(std::sqrt(static_cast<float>(channel)));
                coefficient *= std::sqrt(static_cast<float>(2 * degree + 1));
            }
            if (coefficient != 0.0f)
                juce::FloatVectorOperations::addWithMultiply(outputChannels[destination],
                                                             ambisonicInput.getReadPointer(channel),
                                                             coefficient,
                                                             numSamples);
        }
    }
}

juce::String AmbisonicConfigDecoder::getConfigurationName() const
{
    const juce::SpinLock::ScopedLockType lock(configurationLock);
    return configuration != nullptr ? configuration->name : juce::String();
}

juce::String AmbisonicConfigDecoder::getConfigurationPath() const
{
    const juce::SpinLock::ScopedLockType lock(configurationLock);
    return configuration != nullptr ? configuration->path : juce::String();
}

int AmbisonicConfigDecoder::getConfiguredOutputChannels() const
{
    const juce::SpinLock::ScopedLockType lock(configurationLock);
    return configuration != nullptr ? configuration->outputChannels : 0;
}

int AmbisonicConfigDecoder::getConfiguredOrder() const
{
    const juce::SpinLock::ScopedLockType lock(configurationLock);
    return configuration != nullptr ? configuration->order : 0;
}
