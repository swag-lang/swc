#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for the painter state machine. These assert on the display list a
// drawing emits, which is deterministic and needs no GPU. See [[Testing.assertGolden]].

// The commands a bare begin()/end() pair emits. Every other golden in this folder starts with
// this prelude, so a change here is expected to move a lot of goldens at once.
#test
{
    var painter: Painter
    painter.begin()
    painter.end()
    Testing.assertGolden(&painter, "state.empty")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.clear(Color.fromArgb(Argb.CornflowerBlue))
    painter.end()
    Testing.assertGolden(&painter, "state.clear")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.translateTransform(10, 20)
    painter.scaleTransform(2, 3)
    painter.rotateTransform(90.0'deg)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "state.transform.composed")
}

// A push/pop pair must restore the exact previous transform, so the last Transform command has
// to match the first one.
#test
{
    var painter: Painter
    painter.begin()
    painter.pushTransform()
    painter.translateTransform(5, 7)
    painter.popTransform()
    painter.end()
    Testing.assertGolden(&painter, "state.transform.pushpop")
}

// A translation of zero must not emit anything: the painter filters it out, and losing that
// filter would flood every widget drawing with redundant Transform commands.
#test
{
    var painter: Painter
    painter.begin()
    painter.translateTransform(0, 0)
    painter.end()
    Testing.assertGolden(&painter, "state.transform.identity.noop")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.setClippingRect(10, 10, 100, 50)
    painter.fillRect(0, 0, 200, 200, Color.fromArgb(Argb.Red))
    painter.resetClippingRect()
    painter.end()
    Testing.assertGolden(&painter, "state.clip.rect")
}

// Nested clips intersect; popping restores the enclosing rectangle.
#test
{
    var painter: Painter
    painter.begin()
    painter.pushClippingRect({0, 0, 100, 100})
    painter.pushClippingRect({50, 50, 100, 100})
    painter.fillRect(0, 0, 200, 200, Color.fromArgb(Argb.Red))
    painter.popClippingRect()
    painter.fillRect(0, 0, 200, 200, Color.fromArgb(Argb.Green))
    painter.popClippingRect()
    painter.end()
    Testing.assertGolden(&painter, "state.clip.nested")
}

// Setting the same clipping rectangle twice must emit a single command.
#test
{
    var painter: Painter
    painter.begin()
    painter.setClippingRect(10, 10, 100, 50)
    painter.setClippingRect(10, 10, 100, 50)
    painter.end()
    Testing.assertGolden(&painter, "state.clip.redundant")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.startClippingRegion(.Set)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.White))
    painter.setClippingRegionMode(.Clear)
    painter.endClippingRegion()
    painter.resetClippingRegion()
    painter.end()
    Testing.assertGolden(&painter, "state.clip.region")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.setBlendingMode(.Add)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.setBlendingMode(.Copy)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Green))
    painter.end()
    Testing.assertGolden(&painter, "state.blending")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.setColorMaskAlpha()
    painter.setColorMaskColor()
    painter.end()
    Testing.assertGolden(&painter, "state.colormask")
}

// pushState/popState restores transform, blending and color mask together.
#test
{
    var painter: Painter
    painter.begin()
    painter.pushState()
    painter.setBlendingMode(.Add)
    painter.setColorMaskAlpha()
    painter.translateTransform(3, 4)
    painter.popState()
    painter.end()
    Testing.assertGolden(&painter, "state.pushpop")
}
