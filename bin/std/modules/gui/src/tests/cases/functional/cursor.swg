#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let hidden = Cursor.from(.Hidden)
    let arrow  = Cursor.from(.Arrow)
    var invalid: Cursor

    Swag.require(hidden.isValid() and hidden.isHidden())
    Swag.require(arrow.isValid() and not arrow.isHidden())
    Swag.require(not invalid.isValid() and not invalid.isHidden())

    invalid = hidden
    invalid.clear()
    Swag.require(not invalid.isValid() and not invalid.isHidden())

    var host: Testing.HeadlessHost
    host.setup(320, 200)
    host.app.setCursorHidden(true)
    Swag.require(host.app.isCursorHidden())
    host.app.setCursorHidden(false)
    Swag.require(not host.app.isCursorHidden())
}

// Cursor state can be selected before a renderer creates any native resources.
#test
{
    var app: Application
    app.setCursorHidden(true)
    Swag.require(app.isCursorHidden())
    app.setCursorHidden(false)
    Swag.require(not app.isCursorHidden())
}

// Revealing a pointer during a column drag keeps the resize cursor of the captured header.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let header = Header.create(&host.root, {16, 16, 280, 32})
    header.addColumn("Field", 100)
    header.addColumn("Value", 110)

    let gap = header.themeMetrics().header_Separator
    var point = header.localToSurface(Math.Point{header.itemPositionAt(0) + header.itemWidthAt(0) + gap * 0.5, 12})
    host.surface.surfaceToScreen(&point)
    host.mouseDown(point)
    Swag.require(host.app.mouseCapture() == header)
    let resize = Cursor.from(.ResizeHorizontal)
    Swag.require(host.app.pointerCursor(host.app.mouseCapture()).native.cursor == resize.native.cursor)

    let below = point + Math.Point{25, 70}
    host.moveMouse(below)
    Swag.require(header.itemWidthAt(0) == 125 and host.app.mouseCapture() == header)
    host.app.setCursorHidden(true)
    Swag.require(host.app.pointerCursor(header).isHidden())
    host.app.setCursorHidden(false)
    host.app.setCursorHidden(false)
    Swag.require(host.app.pointerCursor(host.app.mouseCapture()).native.cursor == resize.native.cursor)

    host.mouseUp(below)
    Swag.require(not host.app.mouseCapture())
    host.moveMouse(below)
    let arrow = Cursor.from(.Arrow)
    Swag.require(host.app.pointerCursor(host.mouseTargetAt(below)).native.cursor == arrow.native.cursor)
}
