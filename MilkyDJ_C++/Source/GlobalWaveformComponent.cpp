#include "GlobalWaveformComponent.h"

GlobalWaveformComponent::GlobalWaveformComponent(DeckComponent& a, DeckComponent& b)
    : deckA(a), deckB(b)
{
    startTimerHz(30);
}

void GlobalWaveformComponent::timerCallback()
{
    repaint();
}

void GlobalWaveformComponent::paint(juce::Graphics& g)
{
    auto area = getLocalBounds();
    auto top = area.removeFromTop((area.getHeight() - 8) / 2);
    area.removeFromTop(8);
    auto bottom = area;

    drawZoomedWaveform(g, top, deckA, juce::Colour(184, 243, 74));
    drawZoomedWaveform(g, bottom, deckB, juce::Colour(255, 107, 94));
}

void GlobalWaveformComponent::drawZoomedWaveform(juce::Graphics& g, juce::Rectangle<int> area,
                                                 DeckComponent& deck, juce::Colour accent)
{
    g.setGradientFill(juce::ColourGradient(juce::Colour(25, 29, 27), 0.0f, (float) area.getY(),
                                           juce::Colour(14, 17, 17), 0.0f, (float) area.getBottom(),
                                           false));
    g.fillRoundedRectangle(area.toFloat(), 12.0f);
    g.setColour(juce::Colour(44, 52, 49));
    g.drawRoundedRectangle(area.toFloat().reduced(0.5f), 12.0f, 1.0f);

    const auto deckName = &deck == &deckA ? "A" : "B";
    g.setColour(accent);
    g.fillRoundedRectangle(juce::Rectangle<float>(area.getX() + 7.0f, area.getY() + 7.0f,
                                                   22.0f, 22.0f), 3.0f);
    g.setColour(juce::Colour(248, 250, 250));
    g.setFont(juce::Font(12.0f, juce::Font::bold));
    g.drawText(deckName, area.getX() + 7, area.getY() + 7, 22, 22,
               juce::Justification::centred);

    if (deck.getTrackTotalSamples() <= 0 || deck.getThumbnail().getNumChannels() == 0)
    {
        g.setColour(juce::Colour(151, 163, 169));
        g.setFont(13.0f);
        g.drawText("Drop or load a track", area.reduced(38, 0), juce::Justification::centred);
        return;
    }

    auto& thumb = deck.getThumbnail();
    double totalLen = thumb.getTotalLength();
    double playSec = deck.getPlaybackSeconds();

    double half = windowSeconds * 0.5;
    double start = juce::jlimit(0.0, totalLen, playSec - half);
    double end   = juce::jlimit(0.0, totalLen, playSec + half);

    if ((end - start) < 0.1)
        return;

    // waveform
    g.setColour(accent.withAlpha(0.72f));
    thumb.drawChannels(g, area.reduced(38, 6), start, end, 1.0f);

    // beat grid reale
    const auto& beats = deck.getBeatTimes();
    int beatIndex = 0;
    for (double t : beats)
    {
        if (t < start) { beatIndex++; continue; }
        if (t > end) break;

        double norm = (t - start) / (end - start);
        int x = area.getX() + static_cast<int>(norm * area.getWidth());

        bool bar = (beatIndex % 4 == 0);
        g.setColour(bar ? juce::Colour(90, 90, 90) : juce::Colour(60, 60, 60));
        g.drawLine((float)x, (float)area.getY(), (float)x, (float)area.getBottom(),
                   bar ? 1.5f : 1.0f);

        beatIndex++;
    }

    // playhead fisso al centro
    int centerX = area.getCentreX();
    g.setColour(accent.brighter(0.5f));
    g.drawLine((float)centerX, (float)area.getY(),
               (float)centerX, (float)area.getBottom(), 2.0f);
}