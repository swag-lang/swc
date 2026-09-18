#global public

using Core, Core.Errors, Pixel

// Identifies the backing source of a [[Gui.Movie]].
enum MovieSource
{
    None            // No source is loaded.
    SpriteSheet     // Frames are cells of an [[Gui.ImageList]] atlas.
    Gif             // Frames are decoded from an animated GIF.
    ImageSet        // Frames are decoded through a [[Pixel.ImageReader]].
}

// Plays a sprite sheet or an encoded image set as a sequence of frames.
struct Movie
{
    public
    {
        cachesFrames:         bool = true                 // Whether decoded image-set frames are kept, within `maxCacheBytes`, for later playback and seeking.
        loops:                bool = true                 // Whether playback restarts at the first frame after the last one.
        isPaused:             bool                        // Whether time-based frame advancement is suspended.
        frameDurationSeconds: f32  = 0.05                 // Display duration of a sprite-sheet frame or of a frame with no encoded duration, in seconds; must be positive.
        usesFrameDurations         = true                 // Whether encoded frame durations are honored; when `false`, every frame lasts `frameDurationSeconds`.
        usesEncodedLoops           = true                 // Whether a looping animation stops after its encoded play count.
        maxCacheBytes:        u64  = 67108864             // Budget of cached pixel bytes; zero disables frame caching.
        sigFrameChanged:      SigArray'func||(*Movie)     // Emitted after the current frame changes, through playback or a seek.
        sigDecodeFailed:      SigArray'func||(*Movie)     // Emitted when a frame fails to decode after loading; playback pauses and `failureReason` says why.

        // Where the movie is. Playback advances `frameIndex` and `frame`; seek with `setFrameIndex`.

        readonly
        {
            frameCount:    s32        // Number of frames in the source.
            frameIndex:    s32        // Index of the current frame.
            frame:         Image      // Decoded pixels of the current image-set frame; invalid for a sprite sheet.
            failureReason: String     // Last frame decoding failure, empty once a frame decodes or a source loads.
        }
    }

    // The source the frames come from, and the decoding state that walks it.
    source:              MovieSource = None     // Kind of source the movie plays.
    imgList:             ImageList              // Frames of an image-list source.
    reader:              ImageReader     // Decoder of an image-set source, open while one is loaded.
    cachedFrames:        Array'Image     // Decoded image-set frames retained when caching is enabled.
    elapsedFrameSeconds: f32             // Time accumulated toward the next frame.
    dirtyFrame:          bool            // Whether a seek changed the current frame.
    cachedBytes:         u64             // Pixel bytes held by `cachedFrames`.
    completedLoops:      u32             // Playback cycles completed since the last load, seek, or resume.
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
            if not .loops or (.usesEncodedLoops and .reader.isOpen() and .reader.info.loopCount and .completedLoops >= .reader.info.loopCount)
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
            if not .decodeFrame(nextIndex) do
                return false
        }

        .frameIndex = nextIndex
        .sigFrameChanged.call(me)
        return true
    }
}

impl Movie
{
    // Unloads the source and its cached frames, and resets the playback position.
    //
    // The playback settings, `isPaused` included, keep their values.
    mtd clear()
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

    // Plays the frames of the atlas `imageList` describes, from the first one.
    //
    // `imageList` must be valid. The movie keeps a copy of the description, but the texture stays
    // owned by the caller and must outlive the movie. `isPaused` keeps its value.
    mtd setSpriteSheet(imageList: ImageList)
    {
        Swag.assert(imageList.isValid(), "image list is invalid")
        .clear()
        .source     = .SpriteSheet
        .imgList    = imageList
        .frameCount = .imgList.frameCount
    }

    // Loads the image file `fileName` as the frame source, leaving the movie unchanged on failure.
    //
    // Any image format registered with Pixel is accepted. An animation starts playing with its
    // encoded timing. An independent image set starts paused at its representative image and can
    // be browsed with [[Gui.Movie.setFrameIndex]]. Fails when the file cannot be read or indexed,
    // or when its representative image cannot be decoded.
    mtd load(fileName: string) fail
    {
        var reader     = try ImageReader.load(fileName)
        let firstIndex = reader.info.representativeIndex
        var firstFrame = try reader.read(firstIndex)
        .clear()
        .source     = .ImageSet
        .reader     = #move reader
        .frameCount = cast(s32) .reader.info.frames.count
        .frameIndex = cast(s32) firstIndex
        .frame      = #move firstFrame
        .isPaused   = not .isAnimated()
        .cacheFrame(.frameIndex, .frame)
    }

    // Reports whether the encoded source contains timed animation frames.
    //
    // A sprite sheet answers `false`.
    mtd const isAnimated()->bool => .reader.isOpen() and .reader.info.frames[0].kind == .Animation

    // Returns the number of complete playback cycles since loading, seeking to another frame, or resuming.
    //
    // A cycle completes after the final frame's display duration, including when playback stops
    // there. Seeking alone never completes a cycle, and a single-frame source never completes one.
    // Use this with `loops = false` to handle the end once and decide whether to replay, retain
    // the final frame, or replace the content.
    mtd const completedLoopCount()->u32 => .completedLoops

    // Returns the description of the current frame, or `null` when no image set is loaded.
    //
    // The description belongs to the movie and stays valid until it loads another source or is
    // cleared.
    mtd const frameInfo()->const *ImageFrameInfo?
    {
        if not .reader.isOpen() do
            return null
        return &.reader.info.frames[cast(u32) .frameIndex]
    }

    // Returns how long the current frame is displayed, in seconds.
    //
    // The encoded duration applies when `usesFrameDurations` is set and that duration is positive;
    // otherwise the frame lasts `frameDurationSeconds`.
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
    // Call this on a loading worker before publishing a movie to a GUI control. It does nothing
    // unless the source is an animation and `cachesFrames` is set. Fails when a frame cannot be
    // decoded; the frames cached before it stay cached.
    mtd prepareCache() fail
    {
        if not .isAnimated() or not .cachesFrames do
            return
        while .cachedFrames.count < cast(u64) .frameCount
        {
            if .cachedBytes > .maxCacheBytes or .frame.byteCount > .maxCacheBytes - .cachedBytes do
                break
            let index = cast(s32) .cachedFrames.count
            let frame = try .reader.read(cast(u32) index)
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
    }

    // Shows the frame at `index`, clamped to the loaded frame range.
    //
    // Does nothing without a valid source or when that frame is already current. A seek restarts
    // the display time of the frame and the completed cycle count, then emits `sigFrameChanged`.
    // When the frame fails to decode, the current one stays, playback pauses, and
    // `sigDecodeFailed` is emitted.
    mtd setFrameIndex(index: s32)
    {
        if not .isValid() do
            return

        let targetIndex = Math.clamp(index, 0, .frameCount - 1)
        if targetIndex == .frameIndex do
            return

        switch #complete .source
        {
        case .None:
            break

        case .Gif, .ImageSet:
            if not .decodeFrame(targetIndex) do
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
    //
    // Resuming resets [[Gui.Movie.completedLoopCount]].
    mtd setPaused(paused: bool)
    {
        .isPaused = paused
        if not paused do
            .completedLoops = 0
    }

    // Advances playback by `deltaSeconds` and reports whether the visible state changed.
    //
    // Answers `true` when the frame changed since the previous update, through playback or a seek,
    // and when playback stopped during this update, at the end of its last cycle or on a decode
    // failure. `deltaSeconds` must not be negative.
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
            if not .nextFrame()
            {
                .elapsedFrameSeconds = 0
                break
            }

            hasChanged = true
        }

        return hasChanged or wasDirty or .isPaused
    }
}
