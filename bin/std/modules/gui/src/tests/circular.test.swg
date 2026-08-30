#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var CircularHeadlessChangedCount: u32

func circularHeadlessChanged(c: *Circular)
{
    discard c
    CircularHeadlessChangedCount += 1
}

// setValue/value map through the [min..max] range and emit sigChanged.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    defer host.shutdown()
    CircularHeadlessChangedCount = 0

    let circ = Circular.create(&host.root, {20, 20, 120, 120})
    circ.setBounds(0, 100)
    circ.sigChanged += &circularHeadlessChanged

    circ.setValue(50)
    Swag.assert(Math.abs(circ.value() - 50) < 0.01)
    Swag.assert(Math.abs(circ.lowerRatio - 0.5) < 0.01)
    Swag.assert(CircularHeadlessChangedCount == 1)

    circ.setValue(25)
    Swag.assert(Math.abs(circ.value() - 25) < 0.01)
    Swag.assert(CircularHeadlessChangedCount == 2)

    // Same value again does not re-emit.
    circ.setValue(25)
    Swag.assert(CircularHeadlessChangedCount == 2)
}

// A partial arc applies its start angle exactly once when positioning markers.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    defer host.shutdown()
    let circ = Circular.create(&host.root, {20, 20, 120, 120})
    circ.setAngleRange(Math.Angle.fromDegrees(90), Math.Angle.fromDegrees(270))
    circ.updateGeometry()

    let start = circ.positionAtAngle(circ.valueToAngle(0))
    Swag.assert(start.x > circ.centerX)
    Swag.assert(Math.abs(start.y - circ.centerY) < 0.01)
}

// A range circular keeps two ordered values.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    defer host.shutdown()
    let circ = Circular.create(&host.root, {20, 20, 120, 120}, null, true)
    circ.setBounds(0, 100)

    // Either endpoint can be assigned first because range controls start at the full span.
    circ.setLowerValue(30)
    circ.setUpperValue(70)

    Swag.assert(Math.abs(circ.lowerValue() - 30) < 0.01)
    Swag.assert(Math.abs(circ.upperValue() - 70) < 0.01)
    Swag.assert(circ.lowerRatio <= circ.upperRatio)
}
