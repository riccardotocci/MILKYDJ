#include "DJLookAndFeel.h"

DJLookAndFeel::DJLookAndFeel()
{
    setColour(juce::Slider::backgroundColourId, juce::Colour(13, 17, 16));
    setColour(juce::Slider::trackColourId, juce::Colour(43, 51, 48));
    setColour(juce::Slider::thumbColourId, juce::Colour(85, 214, 190));
    setColour(juce::Slider::textBoxTextColourId, juce::Colour(237, 242, 247));
    setColour(juce::Slider::textBoxBackgroundColourId, juce::Colour(11, 14, 14));
    setColour(juce::Slider::textBoxOutlineColourId, juce::Colour(49, 58, 54));
    setColour(juce::Label::textColourId, juce::Colour(222, 229, 236));
    setColour(juce::TextButton::buttonColourId, juce::Colour(54, 63, 59));
    setColour(juce::TextButton::buttonOnColourId, juce::Colour(66, 78, 72));
    setColour(juce::TextButton::textColourOnId, juce::Colour(248, 250, 252));
    setColour(juce::TextButton::textColourOffId, juce::Colour(248, 250, 252));
    setColour(juce::ToggleButton::tickColourId, juce::Colour(184, 243, 74));
    setColour(juce::DirectoryContentsDisplayComponent::highlightColourId,
              juce::Colour(85, 214, 190).withAlpha(0.24f));
    setColour(juce::DirectoryContentsDisplayComponent::textColourId, juce::Colour(211, 219, 215));
    setColour(juce::FileBrowserComponent::currentPathBoxBackgroundColourId, juce::Colour(12, 15, 15));
    setColour(juce::FileBrowserComponent::filenameBoxBackgroundColourId, juce::Colour(12, 15, 15));
    setColour(juce::TextEditor::backgroundColourId, juce::Colour(12, 15, 15));
    setColour(juce::TextEditor::textColourId, juce::Colour(225, 231, 228));
    setColour(juce::ComboBox::backgroundColourId, juce::Colour(12, 15, 15));
    setColour(juce::ComboBox::textColourId, juce::Colour(225, 231, 228));

    verticalKnob = juce::Drawable::createFromImageData(BinaryData::verticalKnob_svg,
                                                        BinaryData::verticalKnob_svgSize);
    horizontalKnob = juce::Drawable::createFromImageData(BinaryData::horizontalKnob_svg,
                                                          BinaryData::horizontalKnob_svgSize);

    if (!verticalKnob) DBG("Missing SVG: verticalKnob.svg");
    if (!horizontalKnob) DBG("Missing SVG: horizontalKnob.svg");
}

void DJLookAndFeel::drawButtonBackground(juce::Graphics& g, juce::Button& b,
                                         const juce::Colour& background,
                                         bool highlighted, bool down)
{
    auto area = b.getLocalBounds().toFloat().reduced(0.5f);
    const bool isRound = b.getWidth() <= b.getHeight() + 6;
    const float rad = isRound ? area.getWidth() * 0.5f : area.getHeight() * 0.5f;

    juce::Colour base = background;
    if (down)       base = base.darker(0.15f);
    else if (highlighted) base = base.brighter(0.12f);
    if (! b.isEnabled()) base = base.withMultipliedSaturation(0.25f).darker(0.25f);

    g.setGradientFill(juce::ColourGradient(base.brighter(0.08f), 0.0f, area.getY(),
                                           base.darker(0.08f), 0.0f, area.getBottom(), false));
    if (isRound) g.fillEllipse(area);
    else g.fillRoundedRectangle(area, rad);

    g.setColour(juce::Colours::white.withAlpha(highlighted ? 0.18f : 0.07f));
    if (isRound) g.drawEllipse(area, 1.0f);
    else g.drawRoundedRectangle(area, rad, 1.0f);
}

void DJLookAndFeel::drawButtonText(juce::Graphics& g, juce::TextButton& button,
                                   bool, bool)
{
    g.setColour(button.findColour(button.getToggleState()
                                      ? juce::TextButton::textColourOnId
                                      : juce::TextButton::textColourOffId)
                    .withMultipliedAlpha(button.isEnabled() ? 1.0f : 0.5f));
    g.setFont(juce::Font(13.0f, juce::Font::bold));
    g.drawFittedText(button.getButtonText(), button.getLocalBounds().reduced(5, 2),
                     juce::Justification::centred, 1, 0.85f);
}

void DJLookAndFeel::drawLinearSlider(juce::Graphics& g, int x, int y, int w, int h,
                                     float sliderPos, float, float,
                                     const juce::Slider::SliderStyle style, juce::Slider& s)
{
    juce::ignoreUnused(s);
    const bool isVertical = style == juce::Slider::LinearVertical;
    const auto trackBg = findColour(juce::Slider::trackColourId);
    const auto accent = s.findColour(juce::Slider::thumbColourId);
    const auto accent2 = accent.interpolatedWith(juce::Colour(238, 244, 228), 0.24f);

    if (isVertical)
    {
        juce::Rectangle<float> track(x + w * 0.5f - 2.0f, (float) y, 4.0f, (float) h);
        g.setColour(trackBg);
        g.fillRoundedRectangle(track, 2.0f);

        auto active = track.withTop(sliderPos);
        g.setGradientFill(juce::ColourGradient(accent, active.getX(), track.getBottom(),
                                               accent2, active.getX(), track.getY(), false));
        g.fillRoundedRectangle(active, 2.0f);

        const float tw = juce::jmin((float) w, 30.0f);
        const float th = 14.0f;
        juce::Rectangle<float> thumb(x + (w - tw) * 0.5f, sliderPos - th * 0.5f, tw, th);
        g.setColour(juce::Colour(8, 12, 18).withAlpha(0.55f));
        g.fillRoundedRectangle(thumb.translated(0.0f, 1.5f), th * 0.5f);
        g.setColour(juce::Colour(237, 242, 247));
        g.fillRoundedRectangle(thumb, th * 0.5f);
        g.setColour(accent);
        g.fillRoundedRectangle(thumb.withSizeKeepingCentre(tw - 14.0f, 3.0f), 1.5f);
    }
    else
    {
        juce::Rectangle<float> track((float) x, y + h * 0.5f - 2.0f, (float) w, 4.0f);
        g.setColour(trackBg);
        g.fillRoundedRectangle(track, 2.0f);

        auto active = track.withRight(sliderPos);
        g.setGradientFill(juce::ColourGradient(accent, track.getX(), active.getY(),
                                               accent2, track.getRight(), active.getY(), false));
        g.fillRoundedRectangle(active, 2.0f);

        const float diameter = juce::jmin((float) h * 0.8f, 18.0f);
        juce::Rectangle<float> thumb(sliderPos - diameter * 0.5f,
                                     y + (h - diameter) * 0.5f, diameter, diameter);
        g.setColour(juce::Colour(8, 12, 18).withAlpha(0.55f));
        g.fillEllipse(thumb.translated(0.0f, 1.5f));
        g.setColour(juce::Colour(237, 242, 247));
        g.fillEllipse(thumb);
        g.setColour(accent);
        g.drawEllipse(thumb.reduced(2.5f), 2.0f);
    }
}

void DJLookAndFeel::drawToggleButton(juce::Graphics& g, juce::ToggleButton& b,
                                     bool highlighted, bool down)
{
    auto area = b.getLocalBounds().toFloat();
    auto sw = area.removeFromLeft(40.0f).withSizeKeepingCentre(34.0f, 18.0f);
    const bool on = b.getToggleState();

    juce::Colour base = on ? findColour(juce::ToggleButton::tickColourId)
                           : juce::Colour(41, 50, 63);
    if (down) base = base.darker(0.1f);
    else if (highlighted) base = base.brighter(0.1f);

    g.setColour(base);
    g.fillRoundedRectangle(sw, sw.getHeight() * 0.5f);

    const float knob = sw.getHeight() - 5.0f;
    const float knobX = on ? sw.getRight() - knob - 2.5f : sw.getX() + 2.5f;
    g.setColour(juce::Colour(237, 242, 247));
    g.fillEllipse(knobX, sw.getY() + 2.5f, knob, knob);

    g.setColour(juce::Colour(222, 229, 236));
    g.setFont(12.5f);
    g.drawText(b.getButtonText(), area.translated(4.0f, 0.0f),
               juce::Justification::centredLeft);
}