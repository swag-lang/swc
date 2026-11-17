#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// A monitor nobody reported still has a usable scale: one, so a desktop that reports no monitor
// sizes its drawing as an unscaled one rather than as nothing.
#test
{
    var none: Env.Monitor
    Swag.require(none.scaleFactor == 1)
    Swag.require(Env.monitorForPoint(Math.Point{0, 0}).scaleFactor > 0)
}

// A shared boundary belongs to the monitor whose half-open rectangle starts there.
#test
{
    var monitors: Array'Env.Monitor
    var left: Env.Monitor
    left.physicalBounds = {0, 0, 100, 100}
    var right: Env.Monitor
    right.physicalBounds = {100, 0, 100, 100}
    monitors.add(left)
    monitors.add(right)

    let selected = Env.monitorForPointIn(monitors, {100, 50})
    Swag.require(selected.physicalBounds.x == 100)
    Swag.require(Env.monitorForPointIn(monitors, {99, 50}).physicalBounds.x == 0)

    var stacked: Array'Env.Monitor
    var top: Env.Monitor
    top.physicalBounds = {0, 0, 100, 100}
    var bottom: Env.Monitor
    bottom.physicalBounds = {0, 100, 100, 100}
    stacked.add(top)
    stacked.add(bottom)
    Swag.require(Env.monitorForPointIn(stacked, {50, 100}).physicalBounds.y == 100)
}

// Points outside every monitor select the nearest one, and equal distances keep enumeration order.
#test
{
    var monitors: Array'Env.Monitor
    var first: Env.Monitor
    first.physicalBounds = {0, 0, 100, 100}
    var second: Env.Monitor
    second.physicalBounds = {200, 0, 100, 100}
    monitors.add(first)
    monitors.add(second)

    Swag.require(Env.monitorForPointIn(monitors, {175, 50}).physicalBounds.x == 200)
    Swag.require(Env.monitorForPointIn(monitors, {150, 50}).physicalBounds.x == 0)

    var empty: Array'Env.Monitor
    let missing = Env.monitorForPointIn(empty, {0, 0})
    Swag.require(missing.scaleFactor == 1)
    Swag.require(missing.physicalBounds == Math.Rectangle.Zero)
}
