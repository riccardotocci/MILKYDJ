#pragma once
#include <JuceHeader.h>

// Procedural redraw of the Milky DJ galaxy logo (SVG text rendering is unreliable in JUCE).
class MilkyLogoComponent : public juce::Component
{
public:
    void paint(juce::Graphics& g) override
    {
        auto bounds = getLocalBounds().toFloat().reduced(2.0f);
        const auto centre = bounds.getCentre();
        const float rotation = -0.30f;
        const float rx = bounds.getWidth() * 0.44f;
        const float ry = bounds.getHeight() * 0.55f;

        const auto pointAt = [&](float angle, float scale)
        {
            const float x = rx * scale * std::sin(angle);
            const float y = -ry * scale * std::cos(angle);
            return centre + juce::Point<float>(x * std::cos(rotation) - y * std::sin(rotation),
                                               x * std::sin(rotation) + y * std::cos(rotation));
        };

        const auto strokeArc = [&](float from, float to, float scale, float thickness)
        {
            juce::Path arc;
            arc.addCentredArc(centre.x, centre.y, rx * scale, ry * scale,
                              rotation, from, to, true);
            g.strokePath(arc, juce::PathStrokeType(thickness,
                                                   juce::PathStrokeType::curved,
                                                   juce::PathStrokeType::rounded));
        };

        constexpr float pi = juce::MathConstants<float>::pi;
        g.setColour(juce::Colour(225, 231, 228));
        strokeArc(-0.45f, 1.35f, 1.0f, 2.0f);
        strokeArc(0.05f, 1.30f, 0.72f, 1.5f);
        strokeArc(pi - 0.45f, pi + 1.35f, 1.0f, 2.0f);
        strokeArc(pi + 0.05f, pi + 1.30f, 0.72f, 1.5f);

        for (int index = 0; index < 2; ++index)
        {
            g.setColour(index == 0 ? juce::Colour(184, 243, 74)
                                   : juce::Colour(255, 107, 94));
            const float angle = index == 0 ? 0.62f : pi + 0.62f;
            const auto dot = pointAt(angle, 0.55f);
            g.fillEllipse(dot.x - 2.6f, dot.y - 2.6f, 5.2f, 5.2f);
        }

        g.setColour(juce::Colour(238, 242, 240));
        g.setFont(juce::Font(bounds.getHeight() * 0.52f, juce::Font::bold | juce::Font::italic));
        g.drawText("MILKY DJ", bounds, juce::Justification::centred);
    }
};
