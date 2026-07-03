#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

var CircularHeadlessChangedCount: u32

func circularHeadlessChanged(c: *Circular)
{
    discard c
    CircularHeadlessChangedCount += 1
}

// setValue/getValue map through the [min..max] range and emit sigChanged.
#test
{
    var host: GuiHeadlessHost
    host.setup(160, 160)
    CircularHeadlessChangedCount = 0

    let circ = Circular.create(&host.root, {20, 20, 120, 120})
    circ.setMinMax(0, 100)
    circ.sigChanged += &circularHeadlessChanged

    circ.setValue(50)
    @assert(Math.abs(circ.getValue() - 50) < 0.01)
    @assert(Math.abs(circ.value1 - 0.5) < 0.01)
    @assert(CircularHeadlessChangedCount == 1)

    circ.setValue(25)
    @assert(Math.abs(circ.getValue() - 25) < 0.01)
    @assert(CircularHeadlessChangedCount == 2)

    // Same value again does not re-emit.
    circ.setValue(25)
    @assert(CircularHeadlessChangedCount == 2)

    host.shutdown()
}

// A range circular keeps two ordered values.
#test
{
    var host: GuiHeadlessHost
    host.setup(160, 160)

    let circ = Circular.create(&host.root, {20, 20, 120, 120}, null, true)
    circ.setMinMax(0, 100)
    // The right bound must be set first: setValue1 clamps to min(value, value2).
    circ.setValueRight(70)
    circ.setValueLeft(30)

    @assert(Math.abs(circ.getValueLeft() - 30) < 0.01)
    @assert(Math.abs(circ.getValueRight() - 70) < 0.01)
    @assert(circ.value1 <= circ.value2)

    host.shutdown()
}
