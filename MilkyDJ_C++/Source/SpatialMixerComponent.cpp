#include "SpatialMixerComponent.h"

namespace
{
    constexpr const char* sourceNames[] = {
        "A VOCALS", "A DRUMS", "A BASS", "A OTHER",
        "B VOCALS", "B DRUMS", "B BASS", "B OTHER"
    };

    juce::Colour sourceColour(int index)
    {
        static const juce::Colour colours[] = {
            juce::Colour(184, 243, 74), juce::Colour(85, 214, 190),
            juce::Colour(244, 185, 66), juce::Colour(128, 211, 91),
            juce::Colour(255, 107, 94), juce::Colour(243, 143, 69),
            juce::Colour(235, 93, 139), juce::Colour(241, 178, 78)
        };
        return colours[index];
    }

    void configureSlider(juce::Slider& slider, double minimum, double maximum, double initial)
    {
        slider.setRange(minimum, maximum, 0.1);
        slider.setValue(initial, juce::dontSendNotification);
        slider.setSliderStyle(juce::Slider::LinearHorizontal);
        slider.setTextBoxStyle(juce::Slider::TextBoxRight, false, 62, 22);
    }

    juce::Rectangle<float> getSphereBounds(juce::Rectangle<int> availableArea)
    {
        const float diameter = static_cast<float>(juce::jmin(availableArea.getWidth(),
                                                             availableArea.getHeight())) - 12.0f;
        return juce::Rectangle<float>(diameter, diameter).withCentre(availableArea.toFloat().getCentre());
    }

    juce::Point<float> projectDirection(float azimuthDegrees,
                                        float elevationDegrees,
                                        juce::Rectangle<float> sphere)
    {
        const float azimuth = juce::degreesToRadians(azimuthDegrees);
        const float elevation = juce::degreesToRadians(elevationDegrees);
        const float cosElevation = std::cos(elevation);
        const float angularDistance = std::acos(juce::jlimit(-1.0f, 1.0f,
                                                             cosElevation * std::cos(azimuth)));
        const float sinDistance = std::sin(angularDistance);
        const float radius = sphere.getWidth() * 0.5f;

        if (std::abs(sinDistance) < 1.0e-5f)
            return sphere.getCentre();

        const float scale = angularDistance / juce::MathConstants<float>::pi;
        const float x = cosElevation * std::sin(azimuth) / sinDistance;
        const float y = std::sin(elevation) / sinDistance;
        return { sphere.getCentreX() + radius * scale * x,
                 sphere.getCentreY() - radius * scale * y };
    }
}

SpatialMixerComponent::SpatialMixerComponent(AudioEngine& engineRef)
    : engine(engineRef)
{
    setLookAndFeel(&lookAndFeel);

    for (int order = 1; order <= 7; ++order)
        orderSelector.addItem(juce::String(order) + (order == 1 ? "st" : order == 2 ? "nd" : order == 3 ? "rd" : "th"), order);
    orderSelector.setSelectedId(engine.getAmbisonicOrder(), juce::dontSendNotification);
    orderSelector.onChange = [this] { engine.setAmbisonicOrder(orderSelector.getSelectedId()); };

    configureSlider(azimuthSlider, -180.0, 180.0, 0.0);
    configureSlider(elevationSlider, -90.0, 90.0, 0.0);
    configureSlider(widthSlider, 0.0, 180.0, 60.0);
    azimuthSlider.setColour(juce::Slider::thumbColourId, juce::Colour(85, 214, 190));
    elevationSlider.setColour(juce::Slider::thumbColourId, juce::Colour(184, 243, 74));
    widthSlider.setColour(juce::Slider::thumbColourId, juce::Colour(244, 185, 66));
    azimuthSlider.setTextValueSuffix(" deg");
    elevationSlider.setTextValueSuffix(" deg");
    widthSlider.setTextValueSuffix(" deg");

    azimuthSlider.onValueChange = [this]
    {
        getEncoder(selectedSource).setPosition(static_cast<float>(azimuthSlider.getValue()),
                                               getEncoder(selectedSource).getElevation());
    };
    elevationSlider.onValueChange = [this]
    {
        getEncoder(selectedSource).setPosition(getEncoder(selectedSource).getAzimuth(),
                                               static_cast<float>(elevationSlider.getValue()));
    };
    widthSlider.onValueChange = [this]
    {
        getEncoder(selectedSource).setWidth(static_cast<float>(widthSlider.getValue()));
    };

    for (auto* label : { &orderLabel, &azimuthLabel, &elevationLabel, &widthLabel, &selectedLabel, &decoderLabel })
    {
        label->setColour(juce::Label::textColourId, juce::Colour(210, 220, 224));
        addAndMakeVisible(*label);
    }
    addAndMakeVisible(orderSelector);
    addAndMakeVisible(azimuthSlider);
    addAndMakeVisible(elevationSlider);
    addAndMakeVisible(widthSlider);
    addAndMakeVisible(loadDecoderButton);
    loadDecoderButton.setColour(juce::TextButton::buttonColourId, juce::Colour(48, 153, 134));

    selectedLabel.setFont(juce::Font(16.0f, juce::Font::bold));
    decoderLabel.setJustificationType(juce::Justification::centredRight);
    loadDecoderButton.onClick = [this] { loadDecoder(); };

    selectSource(0);
    startTimerHz(30);
}

SpatialMixerComponent::~SpatialMixerComponent()
{
    stopTimer();
    setLookAndFeel(nullptr);
}

AmbisonicStemEncoder& SpatialMixerComponent::getEncoder(int sourceIndex) const
{
    return engine.getStemEncoder(sourceIndex / 4, sourceIndex % 4);
}

juce::Point<float> SpatialMixerComponent::sourceToPoint(int sourceIndex) const
{
    const auto& encoder = getEncoder(sourceIndex);
    return projectDirection(encoder.getAzimuth(), encoder.getElevation(), getSphereBounds(mapBounds));
}

void SpatialMixerComponent::paint(juce::Graphics& graphics)
{
    graphics.fillAll(juce::Colour(9, 11, 12));
    const auto sphere = getSphereBounds(mapBounds);
    graphics.setColour(juce::Colour(15, 19, 18));
    graphics.fillEllipse(sphere);

    graphics.setColour(juce::Colour(51, 61, 57));
    for (int azimuth = -135; azimuth <= 180; azimuth += 45)
    {
        juce::Path longitude;
        for (int elevation = -90; elevation <= 90; elevation += 2)
        {
            const auto point = projectDirection(static_cast<float>(azimuth),
                                                static_cast<float>(elevation), sphere);
            if (elevation == -90)
                longitude.startNewSubPath(point);
            else
                longitude.lineTo(point);
        }
        graphics.strokePath(longitude, juce::PathStrokeType(1.0f));
    }
    for (int elevation = -60; elevation <= 60; elevation += 30)
    {
        juce::Path latitude;
        for (int azimuth = -179; azimuth <= 179; azimuth += 2)
        {
            const auto point = projectDirection(static_cast<float>(azimuth),
                                                static_cast<float>(elevation), sphere);
            if (azimuth == -179)
                latitude.startNewSubPath(point);
            else
                latitude.lineTo(point);
        }
        graphics.strokePath(latitude, juce::PathStrokeType(elevation == 0 ? 1.5f : 1.0f));
    }

    graphics.setColour(juce::Colour(110, 125, 118));
    graphics.drawEllipse(sphere, 2.0f);
    graphics.setFont(11.0f);
    graphics.drawText("FRONT", juce::Rectangle<float>(sphere.getCentreX() - 30.0f,
                                                       sphere.getCentreY() - 9.0f, 60.0f, 18.0f),
                      juce::Justification::centred);
    graphics.drawText("REAR", juce::Rectangle<float>(sphere.getCentreX() - 30.0f,
                                                      sphere.getBottom() - 19.0f, 60.0f, 16.0f),
                      juce::Justification::centred);

    for (int source = 0; source < numSources; ++source)
    {
        const auto point = sourceToPoint(source);
        const bool selected = source == selectedSource;
        graphics.setColour(sourceColour(source).withAlpha(selected ? 0.28f : 0.12f));
        graphics.fillEllipse(point.x - (selected ? 18.0f : 14.0f), point.y - (selected ? 18.0f : 14.0f),
                             selected ? 36.0f : 28.0f, selected ? 36.0f : 28.0f);
        graphics.setColour(sourceColour(source));
        graphics.fillEllipse(point.x - 10.0f, point.y - 10.0f, 20.0f, 20.0f);
        graphics.setColour(juce::Colours::black);
        graphics.setFont(juce::Font(11.0f, juce::Font::bold));
        graphics.drawText(juce::String(source + 1), juce::Rectangle<float>(point.x - 10.0f, point.y - 10.0f, 20.0f, 20.0f),
                          juce::Justification::centred);
    }
}

void SpatialMixerComponent::resized()
{
    auto area = getLocalBounds().reduced(18);
    auto header = area.removeFromTop(34);
    selectedLabel.setBounds(header.removeFromLeft(180));
    orderLabel.setBounds(header.removeFromLeft(54));
    orderSelector.setBounds(header.removeFromLeft(90));
    header.removeFromLeft(12);
    loadDecoderButton.setBounds(header.removeFromLeft(190));
    decoderLabel.setBounds(header);

    area.removeFromTop(12);
    auto controls = area.removeFromBottom(124);
    mapBounds = area;

    const int rowHeight = 34;
    auto positionRow = controls.removeFromTop(rowHeight);
    azimuthLabel.setBounds(positionRow.removeFromLeft(78));
    azimuthSlider.setBounds(positionRow.removeFromLeft((positionRow.getWidth() - 96) / 2));
    positionRow.removeFromLeft(18);
    elevationLabel.setBounds(positionRow.removeFromLeft(88));
    elevationSlider.setBounds(positionRow);

    controls.removeFromTop(8);
    auto widthRow = controls.removeFromTop(rowHeight);
    widthLabel.setBounds(widthRow.removeFromLeft(78));
    widthSlider.setBounds(widthRow.removeFromLeft(320));
}

void SpatialMixerComponent::mouseDown(const juce::MouseEvent& event)
{
    const auto sphere = getSphereBounds(mapBounds);
    if (event.position.getDistanceFrom(sphere.getCentre()) > sphere.getWidth() * 0.5f)
        return;

    int nearest = -1;
    float nearestDistance = 24.0f;
    for (int source = 0; source < numSources; ++source)
    {
        const float distance = sourceToPoint(source).getDistanceFrom(event.position);
        if (distance < nearestDistance)
        {
            nearestDistance = distance;
            nearest = source;
        }
    }
    if (nearest >= 0)
        selectSource(nearest);
    updateSelectedSource(event.position);
}

void SpatialMixerComponent::mouseDrag(const juce::MouseEvent& event)
{
    updateSelectedSource(event.position);
}

void SpatialMixerComponent::updateSelectedSource(juce::Point<float> position)
{
    const auto sphere = getSphereBounds(mapBounds);
    const float radius = sphere.getWidth() * 0.5f;
    auto offset = position - sphere.getCentre();
    const float distance = offset.getDistanceFromOrigin();
    if (distance > radius)
        offset *= radius / distance;

    const float normalizedRadius = juce::jlimit(0.0f, 1.0f,
                                                 offset.getDistanceFromOrigin() / radius);
    const float angularDistance = normalizedRadius * juce::MathConstants<float>::pi;
    const float sinDistance = std::sin(angularDistance);
    const float directionX = normalizedRadius > 1.0e-5f ? offset.x / (normalizedRadius * radius) : 0.0f;
    const float directionY = normalizedRadius > 1.0e-5f ? -offset.y / (normalizedRadius * radius) : 0.0f;
    const float elevation = juce::radiansToDegrees(std::asin(juce::jlimit(-1.0f, 1.0f,
                                                                          directionY * sinDistance)));
    const float azimuth = juce::radiansToDegrees(std::atan2(directionX * sinDistance,
                                                            std::cos(angularDistance)));
    getEncoder(selectedSource).setPosition(azimuth, elevation);
    azimuthSlider.setValue(azimuth, juce::dontSendNotification);
    elevationSlider.setValue(elevation, juce::dontSendNotification);
    repaint(mapBounds.expanded(24));
}

void SpatialMixerComponent::selectSource(int sourceIndex)
{
    selectedSource = juce::jlimit(0, numSources - 1, sourceIndex);
    const auto& encoder = getEncoder(selectedSource);
    azimuthSlider.setValue(encoder.getAzimuth(), juce::dontSendNotification);
    elevationSlider.setValue(encoder.getElevation(), juce::dontSendNotification);
    widthSlider.setValue(encoder.getWidth(), juce::dontSendNotification);
    selectedLabel.setText(juce::String(selectedSource + 1) + "  " + sourceNames[selectedSource],
                          juce::dontSendNotification);
    selectedLabel.setColour(juce::Label::textColourId, sourceColour(selectedSource));
    repaint();
}

void SpatialMixerComponent::loadDecoder()
{
    fileChooser = std::make_unique<juce::FileChooser>("Load IEM decoder configuration", juce::File(), "*.json");
    juce::Component::SafePointer<SpatialMixerComponent> safeThis(this);
    fileChooser->launchAsync(juce::FileBrowserComponent::openMode | juce::FileBrowserComponent::canSelectFiles,
                             [safeThis](const juce::FileChooser& chooser)
                             {
                                 if (safeThis == nullptr || chooser.getResult() == juce::File())
                                     return;
                                 const auto result = safeThis->engine.loadDecoderConfiguration(chooser.getResult());
                                 safeThis->decoderLabel.setText(result.wasOk()
                                     ? safeThis->engine.getDecoderName() + " / "
                                       + juce::String(safeThis->engine.getDecoderOutputChannels()) + " OUT"
                                     : result.getErrorMessage(),
                                     juce::dontSendNotification);
                             });
}

void SpatialMixerComponent::timerCallback()
{
    decoderLabel.setText(engine.getDecoderName() + " / "
                             + juce::String(engine.getDecoderOutputChannels()) + " OUT",
                         juce::dontSendNotification);
    repaint(mapBounds.expanded(24));
}
