#include "JogWheelComponent.h"

JogWheelComponent::JogWheelComponent()
{
    setMouseCursor(juce::MouseCursor::PointingHandCursor);
}

float JogWheelComponent::angleForPoint(juce::Point<float> p) const
{
    auto c = getLocalBounds().toFloat().getCentre();
    return std::atan2(p.y - c.y, p.x - c.x);
}

void JogWheelComponent::mouseDown(const juce::MouseEvent& e)
{
    dragging = true;
    lastAngleRad = angleForPoint(e.position);
}

void JogWheelComponent::mouseDrag(const juce::MouseEvent& e)
{
    if (!dragging) return;

    float current = angleForPoint(e.position);
    float delta = current - lastAngleRad;

    if (delta > juce::MathConstants<float>::pi)  delta -= juce::MathConstants<float>::twoPi;
    if (delta < -juce::MathConstants<float>::pi) delta += juce::MathConstants<float>::twoPi;

    angleRad += delta;
    lastAngleRad = current;
    repaint();
}

void JogWheelComponent::mouseUp(const juce::MouseEvent& e)
{
    juce::ignoreUnused(e);
    dragging = false;
}

void JogWheelComponent::paint(juce::Graphics& g)
{
    auto area = getLocalBounds().toFloat().reduced(6.0f);
    auto center = area.getCentre();

    g.fillAll(juce::Colour(18, 18, 18));

    g.setColour(juce::Colour(35, 35, 35));
    g.fillEllipse(area);

    g.setColour(juce::Colour(70, 70, 70));
    g.drawEllipse(area, 2.0f);

    auto inner = area.reduced(area.getWidth() * 0.18f);
    g.setColour(juce::Colour(50, 50, 50));
    g.fillEllipse(inner);

    g.setColour(juce::Colour(90, 90, 90));
    g.drawEllipse(inner, 1.5f);

    g.saveState();
    g.addTransform(juce::AffineTransform::rotation(angleRad, center.x, center.y));

    auto notch = juce::Rectangle<float>(center.x - 3.0f, area.getY() + 10.0f, 6.0f, 14.0f);
    g.setColour(juce::Colour(200, 200, 200));
    g.fillRoundedRectangle(notch, 2.0f);

    g.restoreState();

    g.setColour(juce::Colour(130, 130, 130));
    g.setFont(12.0f);
    g.drawText("JOG", area.toNearestInt(), juce::Justification::centred);
}