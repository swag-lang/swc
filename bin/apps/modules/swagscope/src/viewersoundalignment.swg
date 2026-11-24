#global internal

using Core, Gui, Audio

private struct AlignmentInput
{
    sound:    SoundFile
    path:     String
    position: f64
}

struct SceneSoundAlignment
{
    using work:      Viewer.BackgroundOperation
    inputs:          Array'AlignmentInput
    offsets:         Array'f64
    sceneActivation: u64
    leader:          u64
}

impl SceneSoundAlignment
{
    const SampleRate    = 1000'u64
    const SearchSamples = 4000's32
    const SampleCount   = 12 * SampleRate

    mtd start(workspace: *ViewerWorkspace, scene: *ViewerScene)
    {
        .inputs.clear()
        .offsets.clear()
        .leader = workspace.mediaLeader(scene)
        .sceneActivation = scene.recent
        for view in scene.views
        {
            let player = ScenePlayer.from(view.document)
            var input: AlignmentInput
            input.position = player.seconds()
            input.path     = view.path
            if player.film and player.film.audio
            {
                input.sound = player.film.audio[]
            }
            elif player.sound
            {
                input.sound = player.sound.sound
            }
            else
            {
                .inputs.clear()
                return
            }

            .inputs.add(#move input)
        }

        let alignment = me
        .submit(func|alignment|()
        {
            catch alignment.calculate() { alignment.offsets.clear() }
        },
                workspace)
    }

    private mtd calculate() fail
    {
        let active = &.inputs[.leader]
        let left   = try .envelope(active)
        if left.count < SampleRate do
            return
        .offsets.resize(.inputs.count)
        for &input, index in .inputs where index != .leader
        {
            if Swag.isCancelled()
            {
                .offsets.clear()
                return
            }

            let right  = try .envelope(input)
            let offset = estimateSoundOffset(left.toSlice(), right.toSlice(), SearchSamples)
            if not offset.reliable
            {
                .offsets.clear()
                return
            }

            .offsets[index] = input.position - active.position + cast(f64, offset.samples) / cast(f64, SampleRate)
        }
    }

    private mtd envelope(input: const *AlignmentInput)->Array'f32 fail
    {
        var result: #returntype
        let sound    = &input.sound
        let rate     = cast(u64, sound.sampleRateHz())
        let channels = sound.numChannels()
        let first    = cast(u64, Math.max(0, input.position - sound.timelineStartSeconds()) * cast(f64, rate))
        if not channels or rate < SampleRate or first >= sound.sampleFrameCount() do
            return result
        let count = Math.min(SampleCount * rate / SampleRate, sound.sampleFrameCount() - first)
        var accumulator: f64
        var next:        u64
        var seen:        u64
        try sound.decodePcm16(first, count, func|result = &result, rate, channels, accumulator = &accumulator, next = &next, seen = &seen|(samples)->bool
        {
            for index in samples.count / channels
            {
                for channel in channels
                {
                    let sample = cast(f64, samples[index * channels + channel]) / 32768
                    accumulator[] += sample * sample
                }

                seen[] += 1
                if seen[] * SampleRate >= (next[] + 1) * rate
                {
                    result.add(cast(f32, Math.sqrt(accumulator[])))
                    accumulator[] = 0
                    next[]        += 1
                }
            }

            return not Swag.isCancelled()
        })
        return result
    }
}

func estimateSoundOffset(first, second: const [..] f32, maximumLag: s32)->{samples: s32, reliable: bool}
{
    var best: f64 = -2.0
    var lag       = 0's32
    var candidate = -maximumLag
    while candidate <= maximumLag
    {
        let score = normalizedSoundCorrelation(first, second, candidate, 16)
        if score > best
        {
            best = score
            lag  = candidate
        }

        candidate += 4
    }

    let coarse = lag
    best = -2
    for delta in -6's32 to 6's32
    {
        let shift = coarse + delta
        if Math.abs(shift) > maximumLag do
            continue
        let score = normalizedSoundCorrelation(first, second, shift, 2)
        if score > best
        {
            best = score
            lag  = shift
        }
    }

    return {samples: lag, reliable: best > 0.65}
}

private func normalizedSoundCorrelation(first, second: const [..] f32, lag: s32, stride: u64)->f64
{
    let a = lag < 0 ? cast(u64, -lag) : 0
    let b = lag > 0 ? cast(u64, lag) : 0
    if a >= first.count or b >= second.count do
        return -2
    let count = Math.min(first.count - a, second.count - b)
    if count < 1500 do
        return -2
    var x, y, xx, yy, xy: f64
    var n:      f64
    var offset: u64
    while offset < count
    {
        let v = cast(f64, first[a + offset])
        let w = cast(f64, second[b + offset])
        x      += v
        y      += w
        xx     += v * v
        yy     += w * w
        xy     += v * w
        n      += 1
        offset += stride
    }

    let variance = (xx - x * x / n) * (yy - y * y / n)
    if variance <= 0.000_001 do
        return -2
    return (xy - x * y / n) / Math.sqrt(variance)
}

impl ViewerWorkspace
{
    mtd alignSceneSound()
    {
        let scene = .scene()
        if not scene or not .isMediaScene() or .alignSound.started do
            return
        SceneSoundAlignment.start(&.alignSound, me, scene)
        if not .alignSound.started do
            .reportAlignmentFailure()
    }

    mtd finishSoundAlignment(evt: *TaskEvent)->bool
    {
        if not .alignSound.claim(evt) do
            return false
        .alignSound.wait()
        let scene = .scene()
        if not scene or scene.recent != .alignSound.sceneActivation do
            return true
        if .alignSound.offsets.count != scene.views.count
        {
            .reportAlignmentFailure()
            return true
        }

        for view, index in scene.views where view.path != .alignSound.inputs[index].path do
            return true
        for &view, index in scene.views do
            view.offset = .alignSound.offsets[index]
        scene.links.mode = .Relative
        scene.links.time = true
        scene.linked     = true
        .refreshMediaCaptions()
        .invalidate()
        catch .primary.saveState()
        return true
    }

    private mtd reportAlignmentFailure()
    {
        let toast = Toast.create(me, "scope.scene.align.failed")
        toast.show(appStrings().scene_AlignFailed, tone: .Failure)
    }
}
