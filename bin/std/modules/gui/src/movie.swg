#global public

using Core, Core.Errors, Pixel

// Identifies the backing source of a [[Gui.Movie]].
enum MovieSource
{
    None            // No source is loaded.
    SpriteSheet     // Frames are cells of an image-list atlas.
    Gif             // Frames are decoded from an animated GIF.
    ImageSet        // Frames are decoded through Pixel's format-neutral image reader.
}

// Plays a sprite sheet or an encoded image set as a sequence of frames.
struct Movie
{
    public
    {
        cachesFrames:         bool = true                 // Cache decoded frames up to maxCacheBytes for later playback and seeking.
        loops:                bool = true                 // Restart at the first frame after the last frame.
        isPaused:             bool                        // Suspend time-based frame advancement.
        frameDurationSeconds: f32  = 0.05                 // Duration for sprite sheets or frames with no encoded duration, in seconds.
        usesFrameDurations         = true                 // Honor encoded frame durations; disable to use frameDurationSeconds for every frame.
        usesEncodedLoops           = true                 // Honor the encoded play count when loops is enabled.
        maxCacheBytes:        u64  = 67108864             // Maximum total cached pixel bytes; zero disables frame caching.
        sigFrameChanged:      SigArray'func||(*Movie)     // Signal emitted after the visible frame changes.
        sigDecodeFailed:      SigArray'func||(*Movie)     // Emitted when later frame decoding fails; playback pauses and failureReason describes the failure.

        // Where the movie is. The playback advances all three; seek with 'setFrameIndex'.

        readonly
        {
            frameCount:    s32        // Number of frames exposed by the source.
            frameIndex:    s32        // Frame currently decoded.
            frame:         Image      // Pixels of the current frame.
            failureReason: String     // Last frame decoding failure, empty after a successful load or seek.
        }
    }

    // The source the frames come from, and the decoding state that walks it.
    source:              MovieSource = None     // Kind of source the movie plays.
    imgList:             ImageList              // Frames of an image-list source.
    reader:              ImageReader
    cachedFrames:        Array'Image     // Decoded image-set frames retained when caching is enabled.
    elapsedFrameSeconds: f32             // Time accumulated toward the next frame.
    dirtyFrame:          bool            // Whether a seek changed the current frame.
    cachedBytes:         u64
    completedLoops:      u32
}

private impl Movie
{
    mtd cacheFrame(index: s32, frame: Image)
    {
        if .cachesFrames and index == .cachedFrames.count and .cachedBytes <= .maxCacheBytes and frame.byteCount <= .maxCacheBytes - .cachedBytes
        {
            .cachedFrames.add(frame)
            .cachedBytes += frame.byteCount
        }
    }

    mtd decodeFrame(index: s32)->bool
    {
        if index < .cachedFrames.count do
            .frame = .cachedFrames[index]
        else
        {
            var frame = catch .reader.read(cast(u32) index) as error
            if error != null
            {
                .failureReason = Errors.message(error)
                .isPaused      = true
                .sigDecodeFailed.call(me)
                return false
            }

            .frame = #move frame
            .cacheFrame(index, .frame)
        }

        .failureReason.clear()
        return true
    }

    mtd nextFrame()->bool
    {
        if .frameCount <= 1 do
            return false

        var nextIndex = .frameIndex + 1
        if nextIndex == .frameCount
        {
            .completedLoops += 1
            if !.loops or (.usesEncodedLoops and .reader.isOpen() and .reader.info.loopCount and .completedLoops >= .reader.info.loopCount)
            {
                .isPaused = true
                return false
            }

            nextIndex = 0
        }

        switch #complete .source
        {
        case .None:
            break

        case .SpriteSheet:
            break

        case .Gif, .ImageSet:
            if !.decodeFrame(nextIndex) do
                return false
        }

        .frameIndex = nextIndex
        .sigFrameChanged.call(me)
        return true
    }

    mtd clearContent()
    {
        Swag.drop(&.imgList, 1)
        Swag.init(&.imgList, 1)
        .reader.close()
        Swag.drop(&.cachedFrames, 1)
        Swag.init(&.cachedFrames, 1)
        Swag.drop(&.frame, 1)
        Swag.init(&.frame, 1)

        .source              = .None
        .frameCount          = 0
        .frameIndex          = 0
        .elapsedFrameSeconds = 0
        .dirtyFrame          = false
        .cachedBytes         = 0
        .completedLoops      = 0
        .failureReason.clear()
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
        Swag.assert(imageList.isValid(), "image list is invalid")
        .clear()
        .source     = .SpriteSheet
        .imgList    = imageList
        .frameCount = .imgList.frameCount
    }

    // Loads any registered image format without changing the movie on failure.
    //
    // Animations start playing with their encoded timing. Independent image sets start
    // paused at their representative image and can be browsed with setFrameIndex.
    mtd load(fileName: string) fail
    {
        var reader     = ImageReader.load(fileName)
        let firstIndex = reader.info.representativeIndex
        var firstFrame = reader.read(firstIndex)
        .clear()
        .source     = .ImageSet
        .reader     = #move reader
        .frameCount = cast(s32) .reader.info.frames.count
        .frameIndex = cast(s32) firstIndex
        .frame      = #move firstFrame
        .isPaused   = !.isAnimated()
        .cacheFrame(.frameIndex, .frame)
    }

    // Reports whether the encoded source contains timed animation frames.
    mtd const isAnimated()->bool => .reader.isOpen() and .reader.info.frames[0].kind == .Animation

    // Returns the indexed description of the current encoded frame, or null for a sprite sheet.
    mtd const frameInfo()->const *ImageFrameInfo?
    {
        if !.reader.isOpen() do
            return null
        return &.reader.info.frames[cast(u32) .frameIndex]
    }

    // Returns the current display duration in seconds; zero encoded delays use the configured fallback.
    mtd const currentFrameDuration()->f32
    {
        if .usesFrameDurations and .reader.isOpen()
        {
            let duration = .reader.info.frames[cast(u32) .frameIndex].durationSeconds
            if duration > 0 do
                return cast(f32) duration
        }

        return .frameDurationSeconds
    }

    // Predecodes the leading animation frames that fit the cache budget, preserving the displayed frame.
    //
    // Call this on a loading worker before publishing a movie to a GUI control.
    mtd prepareCache() fail
    {
        if !.isAnimated() or !.cachesFrames do
            return
        while .cachedFrames.count < cast(u64) .frameCount
        {
            if .cachedBytes > .maxCacheBytes or .frame.byteCount > .maxCacheBytes - .cachedBytes do
                break
            let index = cast(s32) .cachedFrames.count
            let frame = .reader.read(cast(u32) index)
            .cacheFrame(index, frame)
        }
    }

    // Reports whether a playable source is loaded.
    mtd const isValid()->bool
    {
        switch #complete .source
        {
        case .None:           return false
        case .SpriteSheet:    return .imgList.isValid()
        case .Gif, .ImageSet: return .frame.isValid()
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

        case .Gif, .ImageSet:
            if !.decodeFrame(targetIndex) do
                return

        case .SpriteSheet:
            break
        }

        .frameIndex          = targetIndex
        .dirtyFrame          = true
        .elapsedFrameSeconds = 0
        .completedLoops      = 0
        .sigFrameChanged.call(me)
    }

    // Pauses or resumes time-based playback.
    mtd setPaused(paused: bool)
    {
        .isPaused = paused
        if !paused do
            .completedLoops = 0
    }

    // Advances playback by `deltaSeconds` and reports whether the frame changed.
    mtd update(deltaSeconds: f32)->bool
    {
        Swag.assert(deltaSeconds >= 0, "frame delta cannot be negative")
        Swag.assert(.frameDurationSeconds > 0, "frame duration must be positive")

        let wasDirty = .dirtyFrame
        .dirtyFrame = false

        if .isPaused do
            return wasDirty

        var hasChanged = false
        .elapsedFrameSeconds += deltaSeconds
        while .elapsedFrameSeconds >= .currentFrameDuration()
        {
            .elapsedFrameSeconds -= .currentFrameDuration()
            if !.nextFrame()
            {
                .elapsedFrameSeconds = 0
                break
            }

            hasChanged = true
        }

        return hasChanged or wasDirty or .isPaused
    }
}
