#global if #os == Swag.TargetOs.Windows

using Core, Core.Errors, Pixel

// Reads successive frames from one physical screen area into reusable BGRA8 storage.
#[Swag.NoCopy]
struct ScreenFrameSource
{
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
        result.x          = x
        result.y          = y
        result.width      = width
        result.height     = height
        result.drawCursor = drawCursor
        return result
    }

    // Writes bottom-up BGRA8 into `target`, retaining its allocation at a fixed size.
    mtd grabInto(target: *Image) fail =>
        try getScreenRectImageInto(target, .drawCursor, .x, .y, .width, .height)

    // Windows creates its capture device context for each grab, so there is nothing to reopen.
    mtd reopen() fail {}
}
