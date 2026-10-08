#include "EnergyVisualizerComponent.h"

#include <cmath>

namespace
{
    juce::Rectangle<float> fitMap(juce::Rectangle<float> area)
    {
        const float width = juce::jmin(area.getWidth(), area.getHeight() * 2.0f);
        return juce::Rectangle<float>(width, width * 0.5f).withCentre(area.getCentre());
    }

    juce::String orderName(int order)
    {
        if (order == 1) return "1ST";
        if (order == 2) return "2ND";
        if (order == 3) return "3RD";
        return juce::String(order) + "TH";
    }
}

EnergyVisualizerComponent::EnergyVisualizerComponent(const AudioEngine& engineRef)
    : engine(engineRef)
{
    setInterceptsMouseClicks(false, false);
}

juce::Point<float> EnergyVisualizerComponent::projectHammerAitoff(float azimuthDegrees,
                                                                  float elevationDegrees,
                                                                  juce::Rectangle<float> bounds)
{
    const float azimuth = juce::degreesToRadians(azimuthDegrees);
    const float elevation = juce::degreesToRadians(elevationDegrees);
    const float denominator = std::sqrt(1.0f + std::cos(elevation) * std::cos(azimuth * 0.5f));
    const float x = 2.0f * std::sqrt(2.0f) * std::cos(elevation) * std::sin(azimuth * 0.5f) / denominator;
    const float y = std::sqrt(2.0f) * std::sin(elevation) / denominator;
    return { bounds.getCentreX() - x * bounds.getWidth() / (4.0f * std::sqrt(2.0f)),
             bounds.getCentreY() - y * bounds.getHeight() / (2.0f * std::sqrt(2.0f)) };
}

juce::Colour EnergyVisualizerComponent::levelColour(float normalizedLevel)
{
    static constexpr juce::uint32 colours[] = {
        0xff101413, 0xff28685d, 0xff55d6be, 0xffb8f34a, 0xffffb342
    };
    normalizedLevel = juce::jlimit(0.0f, 1.0f, normalizedLevel);
    const float scaled = normalizedLevel * 4.0f;
    const int lower = juce::jmin(3, static_cast<int>(scaled));
    return juce::Colour(colours[lower]).interpolatedWith(juce::Colour(colours[lower + 1]),
                                                         scaled - static_cast<float>(lower));
}

void EnergyVisualizerComponent::paint(juce::Graphics& graphics)
{
    auto area = getLocalBounds().toFloat().reduced(3.0f, 2.0f);
    graphics.setColour(juce::Colour(14, 17, 17));
    graphics.fillRoundedRectangle(area, 8.0f);

    auto header = area.removeFromTop(30.0f);
    auto chipColumn = header.removeFromLeft(48.0f).reduced(2.0f, 2.0f);
    auto normalizationChip = chipColumn.removeFromTop(12.0f);
    chipColumn.removeFromTop(2.0f);
    auto orderChip = chipColumn.removeFromTop(12.0f);

    graphics.setColour(juce::Colour(5, 7, 7));
    graphics.fillRoundedRectangle(normalizationChip, 6.0f);
    graphics.fillRoundedRectangle(orderChip, 6.0f);
    graphics.setColour(juce::Colour(231, 236, 233));
    graphics.setFont(juce::Font(7.5f, juce::Font::bold));
    graphics.drawText("SN3D", normalizationChip, juce::Justification::centred);
    graphics.drawText(orderName(engine.getAmbisonicOrder()), orderChip,
                      juce::Justification::centred);

    graphics.setColour(juce::Colour(235, 239, 237));
    graphics.setFont(juce::Font(12.0f, juce::Font::bold));
    graphics.drawText("Energy Visualizer", header.reduced(2.0f, 0.0f),
                      juce::Justification::centred);

    graphics.setColour(juce::Colour(72, 82, 77));
    graphics.drawHorizontalLine(juce::roundToInt(area.getY()),
                                area.getX() + 2.0f, area.getRight() - 2.0f);

    area.removeFromTop(5.0f);
    const auto map = fitMap(area.reduced(2.0f, 1.0f));
    graphics.setColour(juce::Colour(22, 25, 24));
    graphics.fillEllipse(map);

    juce::Path outline;
    outline.addEllipse(map);
    graphics.saveState();
    graphics.reduceClipRegion(outline);

    const float dotWidth = map.getWidth() / 12.5f;
    const float dotHeight = map.getHeight() / 5.5f;
    for (int point = 0; point < AmbisonicEnergyMeter::numPoints; ++point)
    {
        const float decibels = juce::Decibels::gainToDecibels(engine.getEnergyLevel(point), -60.0f);
        const float normalized = juce::jmap(decibels, -48.0f, 0.0f, 0.0f, 1.0f);
        const auto centre = projectHammerAitoff(AmbisonicEnergyMeter::getAzimuth(point),
                                                AmbisonicEnergyMeter::getElevation(point), map);
        const float alpha = 0.18f + 0.78f * juce::jlimit(0.0f, 1.0f, normalized);
        graphics.setColour(levelColour(normalized).withAlpha(alpha));
        graphics.fillEllipse(centre.x - dotWidth * 0.68f,
                             centre.y - dotHeight * 0.78f,
                             dotWidth * 1.36f,
                             dotHeight * 1.56f);
    }
    graphics.restoreState();

    const auto drawCoordinatePath = [&] (bool longitude, int coordinate, bool major)
    {
        juce::Path path;
        const int start = longitude ? -90 : -180;
        const int end = longitude ? 90 : 180;
        for (int value = start; value <= end; value += 2)
        {
            const float azimuth = longitude ? static_cast<float>(coordinate)
                                             : static_cast<float>(value);
            const float elevation = longitude ? static_cast<float>(value)
                                               : static_cast<float>(coordinate);
            const auto point = projectHammerAitoff(azimuth, elevation, map);
            if (value == start) path.startNewSubPath(point);
            else                path.lineTo(point);
        }
        graphics.setColour(major ? juce::Colour(220, 225, 222)
                                 : juce::Colour(104, 112, 108).withAlpha(0.68f));
        graphics.strokePath(path, juce::PathStrokeType(major ? 1.15f : 0.65f));
    };

    for (int elevation : { -60, -30, 0, 30, 60 })
        drawCoordinatePath(false, elevation, elevation == 0);
    for (int azimuth = -150; azimuth <= 150; azimuth += 30)
        drawCoordinatePath(true, azimuth, azimuth == 0 || std::abs(azimuth) == 90);

    graphics.setColour(juce::Colour(231, 235, 233));
    graphics.drawEllipse(map, 1.4f);

    const auto drawMapLabel = [&] (juce::String text, juce::Point<float> centre,
                                   float width, bool bold)
    {
        graphics.setColour(juce::Colour(235, 239, 237));
        graphics.setFont(juce::Font(bold ? 7.6f : 7.0f,
                                    bold ? juce::Font::bold : juce::Font::plain));
        graphics.drawText(text,
                          juce::Rectangle<float>(width, 10.0f).withCentre(centre),
                          juce::Justification::centred);
    };

    drawMapLabel("TOP", { map.getCentreX(), map.getY() + 5.0f }, 28.0f, true);
    drawMapLabel("BOTTOM", { map.getCentreX(), map.getBottom() - 5.0f }, 42.0f, true);
    drawMapLabel("BACK", { map.getX() + 16.0f, map.getCentreY() - 6.0f }, 30.0f, true);
    drawMapLabel("BACK", { map.getRight() - 16.0f, map.getCentreY() - 6.0f }, 30.0f, true);
    drawMapLabel("LEFT", projectHammerAitoff(90.0f, 0.0f, map).translated(0.0f, -6.0f),
                 28.0f, true);
    drawMapLabel("FRONT", projectHammerAitoff(0.0f, 0.0f, map).translated(0.0f, -6.0f),
                 34.0f, true);
    drawMapLabel("RIGHT", projectHammerAitoff(-90.0f, 0.0f, map).translated(0.0f, -6.0f),
                 34.0f, true);

    for (int azimuth : { 150, 120, 90, 60, 30, 0, -30, -60, -90, -120, -150 })
    {
        auto point = projectHammerAitoff(static_cast<float>(azimuth), 0.0f, map);
        point.y += 6.0f;
        const auto prefix = azimuth > 0 ? "+" : juce::String();
        drawMapLabel(prefix + juce::String(azimuth) + juce::String::charToString(0x00b0),
                     point, 25.0f, false);
    }

    for (int elevation : { 60, 30, -30, -60 })
    {
        auto point = projectHammerAitoff(0.0f, static_cast<float>(elevation), map);
        point.x += 16.0f;
        const auto prefix = elevation > 0 ? "+" : juce::String();
        drawMapLabel(prefix + juce::String(elevation) + juce::String::charToString(0x00b0),
                     point, 28.0f, false);
    }
}
