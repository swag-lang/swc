#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

var SliderHeadlessStartCount:   u32
var SliderHeadlessChangedCount: u32
var SliderHeadlessEndCount:     u32

func sliderHeadlessStart(s: *Slider)   { discard s; SliderHeadlessStartCount += 1 }
func sliderHeadlessChanged(s: *Slider) { discard s; SliderHeadlessChangedCount += 1 }
func sliderHeadlessEnd(s: *Slider)     { discard s; SliderHeadlessEndCount += 1 }

func sliderHeadlessReset()
{
    SliderHeadlessStartCount   = 0
    SliderHeadlessChangedCount = 0
    SliderHeadlessEndCount     = 0
}

// setValue/getValue map through the [min..max] range and clamp.
#test
{
    var host: GuiHeadlessHost
    host.setup(280, 80)
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30})
    slider.setMinMax(0, 100)
    slider.sigStartChange += &sliderHeadlessStart
    slider.sigChanged += &sliderHeadlessChanged
    slider.sigEndChange += &sliderHeadlessEnd

    slider.setValue(50)
    @assert(Math.abs(slider.getValue() - 50) < 0.01)
    @assert(Math.abs(slider.value1 - 0.5) < 0.01)
    @assert(SliderHeadlessChangedCount == 1)
    @assert(SliderHeadlessStartCount == 1)
    @assert(SliderHeadlessEndCount == 1)

    slider.setValue(200)
    @assert(Math.abs(slider.getValue() - 100) < 0.01)

    slider.setValue(-50)
    @assert(Math.abs(slider.getValue() - 0) < 0.01)

    host.shutdown()
}

// Steps snap the value to the nearest multiple.
#test
{
    var host: GuiHeadlessHost
    host.setup(280, 80)
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30})
    slider.setMinMax(0, 10, 1)

    slider.setValue(3.4)
    @assert(Math.abs(slider.getValue() - 3) < 0.01)

    slider.setValue(3.6)
    @assert(Math.abs(slider.getValue() - 4) < 0.01)

    host.shutdown()
}

// A mouse press jumps the value to the click position and dragging updates it.
#test
{
    var host: GuiHeadlessHost
    host.setup(280, 80)
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30})
    slider.setMinMax(0, 100)
    slider.sigStartChange += &sliderHeadlessStart
    slider.sigEndChange += &sliderHeadlessEnd

    host.mouseDown({210, 35})
    @assert(slider.isMoving)
    @assert(host.app.mouseCaptureWnd == slider)
    @assert(SliderHeadlessStartCount == 1)
    let valRight = slider.getValue()
    @assert(valRight > 50)

    host.moveMouse({40, 35})
    let valLeft = slider.getValue()
    @assert(valLeft < 50)
    @assert(valLeft < valRight)

    host.mouseUp({40, 35})
    @assert(!slider.isMoving)
    @assert(host.app.mouseCaptureWnd == null)
    @assert(SliderHeadlessEndCount == 1)

    host.shutdown()
}

// A range slider keeps two ordered values.
#test
{
    var host: GuiHeadlessHost
    host.setup(280, 80)
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30}, null, true)
    slider.setMinMax(0, 100)
    slider.setRangeValues(20, 80)

    @assert(Math.abs(slider.getValueLeft() - 20) < 0.01)
    @assert(Math.abs(slider.getValueRight() - 80) < 0.01)
    @assert(slider.value1 <= slider.value2)

    host.shutdown()
}

// Keyboard control: arrows step the value, Home/End jump to the bounds.
#test
{
    var host: GuiHeadlessHost
    host.setup(280, 80)
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30})
    slider.setMinMax(0, 100)
    slider.setValue(50)
    slider.sigChanged += &sliderHeadlessChanged
    host.focus(slider)

    // Default step is 5% of the range = 5 units.
    host.keyPress(Input.Key.Right)
    @assert(Math.abs(slider.getValue() - 55) < 0.01)
    host.keyPress(Input.Key.Left)
    @assert(Math.abs(slider.getValue() - 50) < 0.01)
    @assert(SliderHeadlessChangedCount == 2)

    host.keyPress(Input.Key.Home)
    @assert(Math.abs(slider.getValue() - 0) < 0.01)
    host.keyPress(Input.Key.End)
    @assert(Math.abs(slider.getValue() - 100) < 0.01)

    // Up/Down mirror Right/Left.
    host.keyPress(Input.Key.Down)
    @assert(Math.abs(slider.getValue() - 95) < 0.01)
    host.keyPress(Input.Key.Up)
    @assert(Math.abs(slider.getValue() - 100) < 0.01)

    host.shutdown()
}

// Keyboard stepping snaps to integer steps when configured.
#test
{
    var host: GuiHeadlessHost
    host.setup(280, 80)
    sliderHeadlessReset()

    let slider = Slider.create(&host.root, {20, 20, 220, 30})
    slider.setMinMax(0, 10, 1)
    slider.setValue(5)
    host.focus(slider)

    host.keyPress(Input.Key.Right)
    @assert(Math.abs(slider.getValue() - 6) < 0.01)
    host.keyPress(Input.Key.Left)
    @assert(Math.abs(slider.getValue() - 5) < 0.01)

    host.shutdown()
}
