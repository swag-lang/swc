#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var SliderHeadlessStartCount:   u32
var SliderHeadlessChangedCount: u32
var SliderHeadlessEndCount:     u32

func sliderHeadlessStart(s: *Slider)
{
    discard s
    SliderHeadlessStartCount += 1
}

func sliderHeadlessChanged(s: *Slider)
{
    discard s
    SliderHeadlessChangedCount += 1
}

func sliderHeadlessEnd(s: *Slider)
{
    discard s
    SliderHeadlessEndCount += 1
}

func sliderHeadlessReset()
{
    SliderHeadlessStartCount   = 0
    SliderHeadlessChangedCount = 0
    SliderHeadlessEndCount     = 0
}

// setValue/value map through the [min..max] range and clamp.
#test
{
    var host: Testing.HeadlessHost
    host.setup(280, 80)
    defer host.shutdown()
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30})
    slider.setBounds(0, 100)
    slider.sigStartChange += &sliderHeadlessStart
    slider.sigChanged     += &sliderHeadlessChanged
    slider.sigEndChange   += &sliderHeadlessEnd

    slider.setValue(50)
    Swag.assert(Math.abs(slider.value() - 50) < 0.01)
    Swag.assert(Math.abs(slider.lowerRatio - 0.5) < 0.01)
    Swag.assert(SliderHeadlessChangedCount == 1)
    Swag.assert(SliderHeadlessStartCount == 1)
    Swag.assert(SliderHeadlessEndCount == 1)

    slider.setValue(200)
    Swag.assert(Math.abs(slider.value() - 100) < 0.01)

    slider.setValue(-50)
    Swag.assert(Math.abs(slider.value() - 0) < 0.01)
}

// Steps snap the value to the nearest multiple.
#test
{
    var host: Testing.HeadlessHost
    host.setup(280, 80)
    defer host.shutdown()
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30})
    slider.setBounds(0, 10, 1)

    slider.setValue(3.4)
    Swag.assert(Math.abs(slider.value() - 3) < 0.01)

    slider.setValue(3.6)
    Swag.assert(Math.abs(slider.value() - 4) < 0.01)
}

// A step that does not divide the range still clamps the upper endpoint exactly.
#test
{
    var host: Testing.HeadlessHost
    host.setup(280, 80)
    defer host.shutdown()
    let slider = Slider.create(&host.root, {20, 20, 220, 30})
    slider.setBounds(0, 10, 6)
    slider.setValue(10)

    Swag.assert(Math.abs(slider.value() - 10) < 0.01)
    Swag.assert(Math.abs(slider.minimum() - 0) < 0.01)
    Swag.assert(Math.abs(slider.maximum() - 10) < 0.01)
    Swag.assert(Math.abs(slider.step() - 6) < 0.01)
}

// A mouse press jumps the value to the click position and dragging updates it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(280, 80)
    defer host.shutdown()
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30})
    slider.setBounds(0, 100)
    slider.sigStartChange += &sliderHeadlessStart
    slider.sigEndChange   += &sliderHeadlessEnd

    host.mouseDown({210, 35})
    Swag.assert(slider.isMoving)
    Swag.assert(host.app.mouseCaptureWnd == slider)
    Swag.assert(SliderHeadlessStartCount == 1)
    let valRight = slider.value()
    Swag.assert(valRight > 50)

    host.moveMouse({40, 35})
    let valLeft = slider.value()
    Swag.assert(valLeft < 50)
    Swag.assert(valLeft < valRight)

    host.mouseUp({40, 35})
    Swag.assert(!slider.isMoving)
    Swag.assert(host.app.mouseCaptureWnd == null)
    Swag.assert(SliderHeadlessEndCount == 1)
}

// A range slider keeps two ordered values.
#test
{
    var host: Testing.HeadlessHost
    host.setup(280, 80)
    defer host.shutdown()
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30}, null, true)
    slider.setBounds(0, 100)
    slider.setRange(20, 80)

    Swag.assert(Math.abs(slider.lowerValue() - 20) < 0.01)
    Swag.assert(Math.abs(slider.upperValue() - 80) < 0.01)
    Swag.assert(slider.lowerRatio <= slider.upperRatio)

    sliderHeadlessReset()
    slider.sigStartChange += &sliderHeadlessStart
    slider.sigChanged     += &sliderHeadlessChanged
    slider.sigEndChange   += &sliderHeadlessEnd
    slider.setRange(-20, 120)
    Swag.assert(Math.abs(slider.lowerValue() - 0) < 0.01)
    Swag.assert(Math.abs(slider.upperValue() - 100) < 0.01)
    Swag.assert(SliderHeadlessStartCount == 1)
    Swag.assert(SliderHeadlessChangedCount == 1)
    Swag.assert(SliderHeadlessEndCount == 1)
}

// Keyboard control: arrows step the value, Home/End jump to the bounds.
#test
{
    var host: Testing.HeadlessHost
    host.setup(280, 80)
    defer host.shutdown()
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30})
    slider.setBounds(0, 100)
    slider.setValue(50)
    slider.sigChanged += &sliderHeadlessChanged
    host.focus(slider)

    // Default step is 5% of the range = 5 units.
    host.keyPress(Input.Key.Right)
    Swag.assert(Math.abs(slider.value() - 55) < 0.01)
    host.keyPress(Input.Key.Left)
    Swag.assert(Math.abs(slider.value() - 50) < 0.01)
    Swag.assert(SliderHeadlessChangedCount == 2)

    host.keyPress(Input.Key.Home)
    Swag.assert(Math.abs(slider.value() - 0) < 0.01)
    host.keyPress(Input.Key.End)
    Swag.assert(Math.abs(slider.value() - 100) < 0.01)

    // Up/Down mirror Right/Left.
    host.keyPress(Input.Key.Down)
    Swag.assert(Math.abs(slider.value() - 95) < 0.01)
    host.keyPress(Input.Key.Up)
    Swag.assert(Math.abs(slider.value() - 100) < 0.01)
}

// Keyboard stepping snaps to integer steps when configured.
#test
{
    var host: Testing.HeadlessHost
    host.setup(280, 80)
    defer host.shutdown()
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30})
    slider.setBounds(0, 10, 1)
    slider.setValue(5)
    host.focus(slider)

    host.keyPress(Input.Key.Right)
    Swag.assert(Math.abs(slider.value() - 6) < 0.01)
    host.keyPress(Input.Key.Left)
    Swag.assert(Math.abs(slider.value() - 5) < 0.01)
}
