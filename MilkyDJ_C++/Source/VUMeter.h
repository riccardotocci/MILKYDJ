#pragma once
#include <juce_gui_basics/juce_gui_basics.h>

class VUMeter : public juce::Component
{
public:
    void setLevel(float l)
    {
        level = juce::jlimit(0.0f, 1.5f, l);
        repaint();
    }

    void paint(juce::Graphics& g) override
    {
        auto r = getLocalBounds().toFloat().reduced(0.5f);
        g.setColour(juce::Colour(10, 14, 21));
        g.fillRoundedRectangle(r, 3.0f);

        auto inner = r.reduced(2.0f);
        auto filled = juce::jlimit(0.0f, inner.getHeight(), level * inner.getHeight());
        juce::Rectangle<float> bar(inner.getX(), inner.getBottom() - filled,
                                   inner.getWidth(), filled);

        juce::ColourGradient grad(juce::Colour(62, 207, 142), bar.getX(), inner.getBottom(),
                                  juce::Colour(242, 92, 92), bar.getX(), inner.getY(), false);
        grad.addColour(0.72, juce::Colour(245, 181, 74));
        g.setGradientFill(grad);
        g.fillRoundedRectangle(bar, 2.0f);

        g.setColour(juce::Colour(38, 48, 62));
        g.drawRoundedRectangle(r, 3.0f, 1.0f);
    }

private:
    float level { 0.0f };
};