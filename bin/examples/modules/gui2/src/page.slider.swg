using Core, Gui, Pixel

func createSliderPage(parent: #nonull *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left = createPanel(parent, "Horizontal", "Single value sliders with continuous and stepped ranges.", layout.left)
    {
        createCaption(left, "Continuous 0..100", 24, 88, 180)
        var slider = Slider.create(left, {24, 116, 320})
        slider.setMinMax(0, 100)
        slider.setValue(42)

        createCaption(left, "Steps of 10", 24, 154, 180)
        slider = Slider.create(left, {24, 182, 320})
        slider.setMinMax(0, 100, 10)
        slider.sliderFlags.add(.ShowSteps)
        slider.setValue(70)
    }

    let right = createPanel(parent, "Range", "Two-handle sliders cover ordering, highlighted intervals and disabled rendering.", layout.right)
    {
        createCaption(right, "Range -10..10", 24, 88, 180)
        var slider = Slider.create(right, {24, 116, 330}, range: true)
        slider.setMinMax(-10, 10)
        slider.setRangeValues(-4, 6)

        createCaption(right, "Disabled range", 24, 154, 180)
        slider = Slider.create(right, {24, 182, 330}, range: true)
        slider.setMinMax(0, 1)
        slider.setRangeValues(0.25, 0.75)
        slider.disable()
    }

    let bottom = createPanel(parent, "Vertical and integer", "Vertical sliders share the same value model and step rendering.", layout.bottom)
    {
        createCaption(bottom, "Vertical", 24, 92, 120)
        var slider = Slider.create(bottom, {48, 126, 32, 96}, vertical: true)
        slider.setMinMax(0, 1, 0.1)
        slider.sliderFlags.add(.ShowSteps)
        slider.setValue(0.65)

        createCaption(bottom, "Range", 104, 92, 120)
        slider = Slider.create(bottom, {112, 126, 32, 96}, range: true, vertical: true)
        slider.setMinMax(0, 1)
        slider.setRangeValues(0.25, 0.75)

        createCaption(bottom, "Integer values", 190, 92, 160)
        slider = Slider.create(bottom, {190, 126, 300})
        slider.setMinMax(0, 255)
        slider.sliderFlags.add(.Integer)
        slider.setValue(128)

        createCaption(bottom, "No highlighted bar", 540, 92, 200)
        slider = Slider.create(bottom, {540, 126, 300})
        slider.sliderFlags &= ~.HilightBar
        slider.setValue(0.35)
    }
}
