#global if #os == Swag.TargetOs.Linux

using Core, Core.Errors, Pixel

// Reads successive frames through the shared native screen source.
#[Swag.NoCopy]
struct ScreenFrameSource
{
    source:     *Screen.Source?
    x:          s32
    y:          s32
    width:      s32
    height:     s32
    drawCursor: bool
    sourceX:    s32
    sourceY:    s32
    fresh:      bool
}

impl ScreenFrameSource
{
    func create(drawCursor: bool, x, y, width, height: s32)->ScreenFrameSource fail
    {
        if width <= 0 or height <= 0 or width > 0x7FFFFFFF's32 / 4 do
            fail BadParameterError{"screen frame source needs positive image dimensions"}
        var result: #returntype
        result.source     = Memory.new'Screen.Source()
        result.source[]   = try Screen.Source.open({x, y, width, height, drawCursor})
        result.x          = x
        result.y          = y
        result.width      = width
        result.height     = height
        result.drawCursor = drawCursor
        result.sourceX    = x
        result.sourceY    = y
        return result
    }

    // Writes bottom-up BGRA8 into `target`, retaining its allocation at a fixed size.
    mtd grabInto(target: *Image, copyUnchanged: bool = true) fail
    {
        discard copyUnchanged
        .fresh = true
        if .x != .sourceX or .y != .sourceY
        {
            Memory.delete(.source)
            .source   = null
            .source   = Memory.new'Screen.Source()
            .source[] = try Screen.Source.open({.x, .y, .width, .height, .drawCursor})
            .sourceX  = .x
            .sourceY  = .y
        }

        discard try .source!.grabInto(target)
    }

    // Reconnects after the display server or its capture connection is lost.
    mtd reopen() fail
    {
        if .x != .sourceX or .y != .sourceY
        {
            Memory.delete(.source)
            .source   = null
            .source   = Memory.new'Screen.Source()
            .source[] = try Screen.Source.open({.x, .y, .width, .height, .drawCursor})
            .sourceX  = .x
            .sourceY  = .y
        }
        else
        {
            try .source!.reopen()
        }
    }

    mtd opDrop() => Memory.delete(.source)
}
