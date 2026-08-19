#global public

using Core, Core.Errors, Pixel

// Identifies the backing source of a [[Gui.Movie]].
enum MovieSource
{
    None            // No source is loaded.
    SpriteSheet     // Frames are cells of an image-list atlas.
    Gif             // Frames are decoded from an animated GIF.
}

// Plays a sprite sheet or animated GIF as a sequence of image frames.
struct Movie
{
    public
    {
        cachesFrames:         bool = true                 // Cache decoded GIF frames for later playback and seeking.
        loops:                bool = true                 // Restart at the first frame after the last frame.
        isPaused:             bool                        // Suspend time-based frame advancement.
        frameDurationSeconds: f32  = 0.05                 // Display duration of each frame, in seconds.
        sigFrameChanged:      SigArray'func||(*Movie)     // Signal emitted after the visible frame changes.

        // Where the movie is. The playback advances all three; seek with 'setFrame'.
        readonly
        {
            frameCount: s32       // Number of frames exposed by the source.
            frameIndex: s32       // Frame currently decoded.
            frame:      Image     // Pixels of the current frame.
        }
    }

    // The source the frames come from, and the decoding state that walks it.
    source:              MovieSource = None     // Kind of source the movie plays.
    imgList:             ImageList              // Frames of an image-list source.
    gif:                 Gif.Decoder            // Decoder of a GIF source.
    bytes:               Array'u8               // Encoded bytes of the source.
    cachedFrames:        Array'Image            // Decoded GIF frames retained when caching is enabled.
    elapsedFrameSeconds: f32                    // Time accumulated toward the next frame.
    dirtyFrame:          bool                   // Whether a seek changed the current frame.
}

private impl Movie
{
    mtd nextFrame()->bool
    {
        if .frameCount <= 1 do
            return false

        var nextIndex = .frameIndex + 1
        if nextIndex == .frameCount
        {
            if !.loops do
                return false
            nextIndex = 0
        }

        switch #complete .source
        {
        case .None:
            break

        case .SpriteSheet:
            break

        case .Gif:
            if nextIndex < .cachedFrames.count
            {
                .frame = .cachedFrames[nextIndex]
            }
            else
            {
                if nextIndex == 0 do
                    .gif.rewind()
                if expect .gif.nextFrame(&.frame) == false do
                    return false
                if .cachesFrames do
                    .cachedFrames.add(.frame)
            }
        }

        .frameIndex = nextIndex
        .sigFrameChanged.call(me)
        return true
    }

    mtd clearContent()
    {
        @drop(&.imgList, 1)
        @init(&.imgList, 1)
        @drop(&.gif, 1)
        @init(&.gif, 1)
        @drop(&.bytes, 1)
        @init(&.bytes, 1)
        @drop(&.cachedFrames, 1)
        @init(&.cachedFrames, 1)
        @drop(&.frame, 1)
        @init(&.frame, 1)

        .source              = .None
        .frameCount          = 0
        .frameIndex          = 0
        .elapsedFrameSeconds = 0
        .dirtyFrame          = false
    }
}

impl Movie
{
    // Removes all content.
    mtd clear()
    {
        .clearContent()
    }

    // Uses a borrowed image-list atlas as the frame source.
    mtd setSpriteSheet(imageList: ImageList)
    {
        Debug.assert(imageList.isValid(), "image list is invalid")
        .clear()
        .source     = .SpriteSheet
        .imgList    = imageList
        .frameCount = .imgList.frameCount
    }

    // Loads an animated GIF from a file without changing the movie on failure.
    mtd load(fileName: string) fail
    {
        var validator: Gif.Decoder
        if !validator.IImageDecoder.format().matches(fileName) do
            fail UnsupportedFormatError{"unsupported format"}

        var bytes = File.readAllBytes(fileName)
        validator.open(bytes.toSlice())
        let frameCount = validator.frameCount()
        if frameCount <= 0 do
            fail InvalidFormatError{"GIF contains no image frame"}
        var firstFrame: Image
        if !validator.nextFrame(&firstFrame) do
            fail InvalidFormatError{"GIF contains no image frame"}

        .clear()
        .source = .Gif
        .bytes  = #move bytes
        expect .gif.open(.bytes.toSlice())
        .frameCount = expect .gif.frameCount()
        discard expect .gif.nextFrame(&.frame)
        if .cachesFrames do
            .cachedFrames.add(.frame)
    }

    // Reports whether a playable source is loaded.
    mtd const isValid()->bool
    {
        switch #complete .source
        {
        case .None:        return false
        case .SpriteSheet: return .imgList.isValid()
        case .Gif:         return .frame.isValid()
        }

        return false
    }

    // Selects a frame, clamping the index to the loaded frame range.
    mtd setFrameIndex(index: s32)
    {
        if !.isValid() do
            return

        let targetIndex = Math.clamp(index, 0, .frameCount - 1)
        if targetIndex == .frameIndex do
            return

        switch #complete .source
        {
        case .None:
            break

        case .Gif:
            if targetIndex < .cachedFrames.count
            {
                .frame = .cachedFrames[targetIndex]
            }
            else
            {
                .gif.rewind()
                if .cachesFrames do
                    .cachedFrames.clear()
                for targetIndex + 1
                {
                    discard expect .gif.nextFrame(&.frame)
                    if .cachesFrames do
                        .cachedFrames.add(.frame)
                }
            }

        case .SpriteSheet:
            break
        }

        .frameIndex = targetIndex
        .dirtyFrame = true
        .sigFrameChanged.call(me)
    }

    // Pauses or resumes time-based playback.
    mtd setPaused(paused: bool)
    {
        .isPaused = paused
    }

    // Advances playback by `deltaSeconds` and reports whether the frame changed.
    mtd update(deltaSeconds: f32)->bool
    {
        Debug.assert(deltaSeconds >= 0, "frame delta cannot be negative")
        Debug.assert(.frameDurationSeconds > 0, "frame duration must be positive")

        let wasDirty = .dirtyFrame
        .dirtyFrame = false

        if .isPaused do
            return wasDirty

        var hasChanged = false
        .elapsedFrameSeconds += deltaSeconds
        while .elapsedFrameSeconds >= .frameDurationSeconds
        {
            .elapsedFrameSeconds -= .frameDurationSeconds
            if !.nextFrame()
            {
                .elapsedFrameSeconds = 0
                break
            }

            hasChanged = true
        }

        return hasChanged or wasDirty
    }
}
