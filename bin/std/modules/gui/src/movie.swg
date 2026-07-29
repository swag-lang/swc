#global public

using Core, Core.Errors, Pixel

// Selects movie source.
enum MovieSource
{
    None // No option is selected.
    SpriteSheet // Selects sprite sheet.
    Gif // Selects gif.
}

// Represents movie.
struct Movie
{
    enableCache:     bool = true // Enable cache associated with this value.
    mustLoop:        bool = true // Must loop associated with this value.
    inPause:         bool // In pause associated with this value.
    playFreq:        f32  = 0.05 // Play freq associated with this value.
    sigFrameChanged: SigArray'func||(*Movie) // Signal emitted when frame changed.

    numFrames:  s32 // Num frames associated with this value.
    frameIndex: s32 // Index of frame.
    frame:      Image // Frame associated with this value.

    source:      MovieSource = None // Source associated with this value.
    imgList:     ImageList // Img list associated with this value.
    gif:         Gif.Decoder // Gif associated with this value.
    bytes:       Array'u8 // Bytes associated with this value.
    cacheFrames: Array'Image // Cache frames associated with this value.
    currentTime: f32 // Current time associated with this value.
    dirtyFrame:  bool // Dirty frame associated with this value.
}

private impl Movie
{
    mtd nextFrame()
    {
        if .frameIndex == .numFrames - 1
        {
            if .mustLoop do
                .frameIndex = 0
            else do
                return
        }
        else do
            .frameIndex += 1

        switch #complete .source
        {
        case .None:
            break

        case .SpriteSheet:
            break

        case .Gif:
            if .frameIndex < .cacheFrames.count
            {
                .frame = .cacheFrames[.frameIndex]
            }
            elif expect .gif.nextFrame(&.frame) == false
            {
                if .mustLoop
                {
                    .gif.rewind()
                    .frameIndex = 0
                    discard expect .gif.nextFrame(&.frame)
                }
            }
            elif .enableCache
            {
                .cacheFrames.add(.frame)
            }
        }

        .sigFrameChanged.call(me)
    }
}

impl Movie
{
    // Removes all content.
    mtd clear()
    {
        .cacheFrames.clear()
        .bytes.clear()
        .source = .None
        .frame.release()
        .numFrames   = 0
        .frameIndex  = 0
        .currentTime = 0
    }

    // Associate an image list
    mtd set(imageList: ImageList)
    {
        .clear()
        .source    = .SpriteSheet
        .imgList   = imageList
        .numFrames = .imgList.totalFrames
    }

    // Associate a filename
    mtd set(fileName: string) fail
    {
        .clear()
        if .gif.IImageDecoder.canDecode(fileName)
        {
            .source = .Gif
            .bytes  = File.readAllBytes(fileName)
            .gif.init(.bytes.toSlice(), true)
            .numFrames = .gif.getNumFrames()
            .gif.getFrame(&.frame)
            discard .gif.nextFrame(&.frame)
            if .enableCache do
                .cacheFrames.add(.frame)
        }
        else
        {
            fail UnsupportedFormatError{"unsupported format"}
        }
    }

    // Returns true if the movie has valid content
    mtd isValid()->bool
    {
        switch #complete .source
        {
        case .None:        return false
        case .SpriteSheet: return .imgList.texture.valid
        case .Gif:         return .frame.pixels.buffer != null
        }

        return false
    }

    // Set the current video frame
    mtd setFrameIndex(idx: s32)
    {
        if idx == .frameIndex do
            return
        .frameIndex = Math.min(idx, .numFrames)

        switch #complete .source
        {
        case .None:
            break

        case .Gif:
            .frameIndex = Math.min(idx, .numFrames)
            if .frameIndex < .cacheFrames.count
            {
                .frame      = .cacheFrames[.frameIndex]
                .dirtyFrame = true
            }

        case .SpriteSheet:
            break
        }

        .sigFrameChanged.call(me)
    }

    // Set/Reset pause state
    mtd pause(state: bool)
    {
        .inPause = state
    }

    // Update timing and change frames
    mtd update(dt: f32)->bool
    {
        let wasDirty = .dirtyFrame
        .dirtyFrame = false

        if .inPause do
            return wasDirty

        var hasChanged = false
        .currentTime += dt
        while .currentTime > .playFreq
        {
            hasChanged   = true
            .currentTime -= .playFreq
            .nextFrame()
        }

        return hasChanged or wasDirty
    }
}
