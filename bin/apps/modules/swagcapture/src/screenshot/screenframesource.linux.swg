#global if #os == Swag.TargetOs.Linux

using Core, Core.Errors, Pixel

// Reads successive frames from one physical screen area over a persistent X11 connection.
#[Swag.NoCopy]
struct ScreenFrameSource
{
    capture:    X11Capture
    x:          s32
    y:          s32
    width:      s32
    height:     s32
    drawCursor: bool
}

impl ScreenFrameSource
{
    func create(drawCursor: bool, x, y, width, height: s32)->ScreenFrameSource fail
    {
        if width <= 0 or height <= 0 or width > 0x7FFFFFFF's32 / 4 do
            fail BadParameterError{"screen frame source needs positive image dimensions"}
        var result: #returntype
        result.capture    = try X11Capture.create()
        result.x          = x
        result.y          = y
        result.width      = width
        result.height     = height
        result.drawCursor = drawCursor
        return result
    }

    // Writes bottom-up BGRA8 into `target`, retaining its allocation at a fixed size.
    mtd grabInto(target: *Image) fail =>
        try .capture.imageInto(target, .drawCursor, .x, .y, .width, .height)

    // Reconnects after the display server or its capture connection is lost.
    mtd reopen() fail
    {
        .capture = try X11Capture.create()
    }
}
