#global public

using Core, Pixel

// Reports how a finite animation ended.
enum AnimationResult
{
    Completed     // Reached the requested endpoint.
    Cancelled     // Stopped before reaching the requested endpoint.
}

// Selects the interpolation curve applied to normalized animation progress.
//
// The toolkit does not own its curves: a named easing is one shape of [[Core.Math.Curve]], and the
// scheduler evaluates it through that type like any curve an application authors itself. Set
// [[Gui.AnimationOptions.curve]] instead to drive a track with a shape that has no name here.
//
// The last five curves leave the zero-to-one interval on purpose: an anticipating or overshooting
// track passes beyond its endpoints before settling on them. Use them for position, scale, and
// other geometry that can travel past its target, and keep the first four for opacity and color,
// where an out-of-range value is clamped rather than seen.
alias AnimationEasing = Math.CurvePreset

// Selects which endpoint an animation starts from.
enum AnimationDirection
{
    Forward     // Runs from the supplied start value to the end value.
    Reverse     // Runs from the supplied end value to the start value.
}

// Selects the work invalidated after an animation update.
enum AnimationImpact
{
    Paint      // Repaints only the target window.
    Layout     // Reapplies the target's parent layout before repainting.
}

// Classifies an animation for reduced-motion policy.
enum AnimationMotion
{
    Decorative     // Completes immediately when reduced motion is active.
    Essential      // Continues because it communicates ongoing work or progress.
}

// Selects how an application resolves the system reduced-motion preference.
enum MotionPreference
{
    System      // Follows the platform client-area-animation preference.
    Full        // Enables decorative motion regardless of the platform preference.
    Reduced     // Completes decorative motion immediately.
}

// Identifies one independently retargetable animation property of a window.
//
// Use the same name for successive writes to one property. A replacement then starts from the
// value currently on screen rather than from its authored start value.
#[Swag.Opaque]
struct AnimationChannel
{
    internal value: u64
}

impl AnimationChannel
{
    // Creates a stable channel from an application-defined name.
    func from(name: string)->AnimationChannel
    {
        return {Hash.Crc64.compute(name) & 0x7FFF_FFFF_FFFF_FFFF}
    }

    internal func fromPointer(value: *void)->AnimationChannel
    {
        return {cast(u64) value | 0x8000_0000_0000_0000}
    }
}

// Configures one finite animation track.
struct AnimationOptions
{
    public
    {
        delay:            Time.Duration                        // Non-negative time kept at the start value before progress begins.
        duration:         Time.Duration      = 150'ms          // Non-negative time of one play, between the start and end values.
        easing:           AnimationEasing    = .EaseInOut      // Named curve applied to normalized progress; ignored once 'curve' is set.
        direction:        AnimationDirection = .Forward        // Endpoint from which the track starts.
        repeatCount:      u32                = 1               // Number of successive plays; zero repeats until the track is cancelled.
        autoReverse:      bool                                 // Whether every second play runs back toward the value it started from.
        impact:           AnimationImpact    = .Paint          // Work invalidated by each update.
        motion:           AnimationMotion    = .Decorative     // Reduced-motion classification.
        preserveProgress: bool                                 // Whether retargeting keeps normalized progress.

        // Authored curve applied to normalized progress instead of `easing`.
        //
        // The scheduler borrows it rather than copying it, so it has to outlive every track it was
        // given to — a curve owned by the animated window, by its theme, or by the application all
        // qualify, and a temporary declared next to the call does not. Leave it null to use `easing`.
        curve: #null const *Math.Curve
    }
}

// Identifies one scheduler-owned animation without retaining its target.
#[Swag.Opaque]
struct AnimationHandle
{
    internal id: u64
}

impl AnimationHandle
{
    // Reports whether this value names an animation that was started.
    mtd const isValid()->bool => .id != 0
}

// Callback invoked after an animation or one of its tracks ends.
alias AnimationCompletion      = func||(AnimationResult)

alias AnimationF32Update       = func||(*Wnd, f32)                // Receives the live target and current scalar value.
alias AnimationColorUpdate     = func||(*Wnd, Color)              // Receives the live target and current color value.
alias AnimationPointUpdate     = func||(*Wnd, Math.Point)         // Receives the live target and current point value.
alias AnimationVector4Update   = func||(*Wnd, Math.Vector4)       // Receives the live target and current vector value.
alias AnimationRectangleUpdate = func||(*Wnd, Math.Rectangle)     // Receives the live target and current rectangle value.

private enum AnimationValueKind
{
    F32
    Color
    Point
    Vector4
    Rectangle
}

private enum AnimationGroupKind
{
    Parallel
    Sequence
}

private struct AnimationTrack
{
    target:  *Wnd = undefined
    channel: AnimationChannel
    options: AnimationOptions
    kind:    AnimationValueKind
    step:    u32

    elapsedSeconds: f64
    finished:       bool

    fromF32, toF32, currentF32:                   f32
    fromColor, toColor, currentColor:             Math.Vector4
    fromPoint, toPoint, currentPoint:             Math.Point
    fromVector4, toVector4, currentVector4:       Math.Vector4
    fromRectangle, toRectangle, currentRectangle: Math.Rectangle

    updateF32:       #null AnimationF32Update
    updateColor:     #null AnimationColorUpdate
    updatePoint:     #null AnimationPointUpdate
    updateVector4:   #null AnimationVector4Update
    updateRectangle: #null AnimationRectangleUpdate
    completion:      #null AnimationCompletion
}

// Collects tracks that start together or one after another.
//
// Build the group, then transfer it to [[Gui.Animator.start]] with `#move`.
#[Swag.Opaque, Swag.NoCopy]
struct AnimationGroup
{
    internal
    {
        kind:       AnimationGroupKind
        tracks:     ArrayPtr'AnimationTrack
        completion: #null AnimationCompletion
    }
}

private impl AnimationGroup
{
    mtd addTrack(target: *Wnd, channel: AnimationChannel, options: AnimationOptions, kind: AnimationValueKind)->*AnimationTrack
    {
        Debug.assert(target != null)
        Debug.assert(options.delay.seconds >= 0)
        Debug.assert(options.duration.seconds >= 0)
        let track = Memory.new'AnimationTrack()
        track.target  = target
        track.channel = channel
        track.options = options
        track.kind    = kind
        if .kind == .Sequence do
            track.step = cast(u32) .tracks.count
        .tracks.add(track)
        return track
    }
}

impl AnimationGroup
{
    // Creates a group whose tracks advance together.
    func parallel()->AnimationGroup
    {
        var result: retval
        result.kind = .Parallel
        return result
    }

    // Creates a group whose tracks advance in insertion order.
    //
    // A track that repeats forever never releases its turn, so keep an endless track in a
    // parallel group or make it the last step.
    func sequence()->AnimationGroup
    {
        var result: retval
        result.kind = .Sequence
        return result
    }

    // Sets the callback invoked once after the complete group ends.
    mtd setCompletion(completion: #null AnimationCompletion)
    {
        .completion = completion
    }

    // Adds a scalar track.
    mtd addF32(target: *Wnd, channel: AnimationChannel, from, destination: f32, update: AnimationF32Update, options: AnimationOptions = {}, completion: #null AnimationCompletion = null)
    {
        let track = .addTrack(target, channel, options, .F32)
        track.fromF32, track.currentF32 = from
        track.toF32                     = destination
        track.updateF32                 = update
        track.completion                = completion
    }

    // Adds a color track, including alpha.
    mtd addColor(target: *Wnd, channel: AnimationChannel, from, destination: Color, update: AnimationColorUpdate, options: AnimationOptions = {}, completion: #null AnimationCompletion = null)
    {
        let track = .addTrack(target, channel, options, .Color)
        track.fromColor, track.currentColor = from.toVector4()
        track.toColor     = destination.toVector4()
        track.updateColor = update
        track.completion  = completion
    }

    // Adds a two-dimensional point track.
    mtd addPoint(target: *Wnd, channel: AnimationChannel, from, destination: Math.Point, update: AnimationPointUpdate, options: AnimationOptions = {}, completion: #null AnimationCompletion = null)
    {
        let track = .addTrack(target, channel, options, .Point)
        track.fromPoint, track.currentPoint = from
        track.toPoint     = destination
        track.updatePoint = update
        track.completion  = completion
    }

    // Adds a four-component vector track.
    mtd addVector4(target: *Wnd, channel: AnimationChannel, from, destination: Math.Vector4, update: AnimationVector4Update, options: AnimationOptions = {}, completion: #null AnimationCompletion = null)
    {
        let track = .addTrack(target, channel, options, .Vector4)
        track.fromVector4, track.currentVector4 = from
        track.toVector4     = destination
        track.updateVector4 = update
        track.completion    = completion
    }

    // Adds a rectangle track.
    mtd addRectangle(target: *Wnd, channel: AnimationChannel, from, destination: Math.Rectangle, update: AnimationRectangleUpdate, options: AnimationOptions = {}, completion: #null AnimationCompletion = null)
    {
        let track = .addTrack(target, channel, options, .Rectangle)
        track.fromRectangle, track.currentRectangle = from
        track.toRectangle     = destination
        track.updateRectangle = update
        track.completion      = completion
    }
}

private struct AnimationRun
{
    id:              u64
    currentStep:     u32
    cancelRequested: bool
    tracks:          ArrayPtr'AnimationTrack
    completion:      #null AnimationCompletion
}

// Advances finite GUI animations and owns their callbacks until completion or cancellation.
#[Swag.Opaque, Swag.NoCopy]
struct Animator
{
    internal
    {
        app:           #null *Application
        animations:    ArrayPtr'AnimationRun
        nextId:        u64 = 1
        duringAdvance: bool
    }
}

private impl Animator
{
    // Returns the value the track holds at normalized `progress`.
    //
    // An authored curve wins over the named one, and both are read through [[Core.Math.Curve]], so a
    // preview that plots either shape plots what the track will really do.
    func directedFactor(track: *AnimationTrack, progress: f32)->f32
    {
        let directed = track.options.direction == .Forward ? progress : 1 - progress
        if track.options.curve do
            return track.options.curve.evaluateNormalized(directed)
        return Math.Curve.shared(track.options.easing).evaluateNormalized(directed)
    }

    // Returns the normalized progress a track holds once every play is over.
    //
    // A ping-pong track ends where it started whenever it plays an even number of times, and an
    // endless one is treated as even because that is the value it keeps returning to.
    func restProgress(track: *AnimationTrack)->f32
    {
        if !track.options.autoReverse do
            return 1
        return track.options.repeatCount & 1 ? 1 : 0
    }

    // Returns the elapsed time at which a track stops advancing, or an unreachable time while it repeats forever.
    func totalSeconds(track: *AnimationTrack)->f64
    {
        if !track.options.repeatCount do
            return Swag.F64.Max
        return track.options.delay.seconds + track.options.duration.seconds * cast(f64) track.options.repeatCount
    }

    func isElapsed(track: *AnimationTrack)->bool
    {
        return track.options.repeatCount != 0 and track.elapsedSeconds >= totalSeconds(track)
    }

    func progress(track: *AnimationTrack)->f32
    {
        let delay = track.options.delay.seconds
        if track.elapsedSeconds <= delay do
            return 0
        let duration = track.options.duration.seconds
        if duration <= 0 do
            return restProgress(track)

        // The last play holds its final frame instead of wrapping to the beginning again.
        let plays = (track.elapsedSeconds - delay) / duration
        var index = Math.floor(plays)
        if track.options.repeatCount and index > cast(f64) (track.options.repeatCount - 1) do
            index = cast(f64) (track.options.repeatCount - 1)

        let local = Math.saturate(cast(f32) (plays - index))
        if track.options.autoReverse and cast(u64) index & 1 do
            return 1 - local
        return local
    }

    func lerpPoint(source, destination: Math.Point, factor: f32)->Math.Point
    {
        return {Math.lerp(source.x, destination.x, factor), Math.lerp(source.y, destination.y, factor)}
    }

    func lerpRectangle(source, destination: Math.Rectangle, factor: f32)->Math.Rectangle
    {
        return {
            Math.lerp(source.x, destination.x, factor),
            Math.lerp(source.y, destination.y, factor),
            Math.lerp(source.width, destination.width, factor),
            Math.lerp(source.height, destination.height, factor)}
    }

    func lerpColor(source, destination: Math.Vector4, factor: f32)->Math.Vector4
    {
        var start = source
        var end   = destination
        if start.w == 0
        {
            start.x = end.x
            start.y = end.y
            start.z = end.z
        }

        if end.w == 0
        {
            end.x = start.x
            end.y = start.y
            end.z = start.z
        }

        return Math.Vector4.lerp(start, end, factor)
    }

    mtd applyImpact(track: *AnimationTrack)
    {
        if track.target.isPendingDestroy do
            return
        if track.options.impact == .Layout
        {
            track.target.invalidateLayout()
            if track.target.parent do
                track.target.parent.applyLayout()
            else do
                track.target.applyLayout()
        }

        track.target.invalidate()
    }

    mtd applyTrack(track: *AnimationTrack, progress: f32)
    {
        let factor = directedFactor(track, progress)
        switch #complete track.kind
        {
        case .F32:
            track.currentF32 = Math.lerp(track.fromF32, track.toF32, factor)
            track.updateF32!(track.target, track.currentF32)

        case .Color:
            track.currentColor = lerpColor(track.fromColor, track.toColor, factor)
            track.updateColor!(track.target, Color.fromVector4(track.currentColor))

        case .Point:
            track.currentPoint = lerpPoint(track.fromPoint, track.toPoint, factor)
            track.updatePoint!(track.target, track.currentPoint)

        case .Vector4:
            track.currentVector4 = Math.Vector4.lerp(track.fromVector4, track.toVector4, factor)
            track.updateVector4!(track.target, track.currentVector4)

        case .Rectangle:
            track.currentRectangle = lerpRectangle(track.fromRectangle, track.toRectangle, factor)
            track.updateRectangle!(track.target, track.currentRectangle)
        }

        .applyImpact(track)
    }

    mtd completeTrack(track: *AnimationTrack, result: AnimationResult)
    {
        if track.finished do
            return
        track.finished = true
        if track.completion do
            track.completion(result)
    }

    mtd finishAt(index: u64, result: AnimationResult)
    {
        let run = .animations[index]!
        .animations.removeAtOrdered(index)
        for track in run.tracks
        {
            if !track!.finished do
                .completeTrack(track!, result)
        }

        if run.completion do
            run.completion(result)
        Memory.delete(run)
    }

    mtd findTrack(target: *Wnd, channel: AnimationChannel)->#null *AnimationTrack
    {
        for run in .animations
        {
            for track in run!.tracks
            {
                let value = track!
                if !value.finished and value.target == target and value.channel == channel do
                    return value
            }
        }

        return null
    }

    mtd requestCancellation(target: *Wnd)
    {
        var index = .animations.count
        while index
        {
            index -= 1
            let run     = .animations[index]!
            var matches = false
            for track in run.tracks
            {
                if track!.target == target
                {
                    matches = true
                    break
                }
            }

            if !matches do
                continue
            if .duringAdvance do
                run.cancelRequested = true
            else do
                .finishAt(index, .Cancelled)
        }
    }

    mtd requestCancellation(target: *Wnd, channel: AnimationChannel)
    {
        var index = .animations.count
        while index
        {
            index -= 1
            let run     = .animations[index]!
            var matches = false
            for track in run.tracks
            {
                let value = track!
                if value.target != target do
                    continue
                if value.channel != channel do
                    continue
                matches = true
                break
            }

            if !matches do
                continue
            if .duringAdvance do
                run.cancelRequested = true
            else do
                .finishAt(index, .Cancelled)
        }
    }

    mtd preserveCurrent(track, previous: *AnimationTrack)
    {
        let raw = progress(previous)
        if !track.options.preserveProgress or raw <= 0
        {
            switch #complete track.kind
            {
            case .F32:
                track.currentF32 = previous.currentF32
                if track.options.direction == .Forward do
                    track.fromF32 = track.currentF32
                else do
                    track.toF32 = track.currentF32

            case .Color:
                track.currentColor = previous.currentColor
                if track.options.direction == .Forward do
                    track.fromColor = track.currentColor
                else do
                    track.toColor = track.currentColor

            case .Point:
                track.currentPoint = previous.currentPoint
                if track.options.direction == .Forward do
                    track.fromPoint = track.currentPoint
                else do
                    track.toPoint = track.currentPoint

            case .Vector4:
                track.currentVector4 = previous.currentVector4
                if track.options.direction == .Forward do
                    track.fromVector4 = track.currentVector4
                else do
                    track.toVector4 = track.currentVector4

            case .Rectangle:
                track.currentRectangle = previous.currentRectangle
                if track.options.direction == .Forward do
                    track.fromRectangle = track.currentRectangle
                else do
                    track.toRectangle = track.currentRectangle
            }

            return
        }

        track.elapsedSeconds = track.options.delay.seconds + raw * track.options.duration.seconds
        let factor = directedFactor(track, raw)
        if (track.options.direction == .Forward and factor >= 1) or
           (track.options.direction == .Reverse and factor <= 0)
        {
            track.elapsedSeconds = 0
            switch #complete track.kind
            {
            case .F32:
                track.currentF32 = previous.currentF32
                if track.options.direction == .Forward do
                    track.fromF32 = track.currentF32
                else do
                    track.toF32 = track.currentF32

            case .Color:
                track.currentColor = previous.currentColor
                if track.options.direction == .Forward do
                    track.fromColor = track.currentColor
                else do
                    track.toColor = track.currentColor

            case .Point:
                track.currentPoint = previous.currentPoint
                if track.options.direction == .Forward do
                    track.fromPoint = track.currentPoint
                else do
                    track.toPoint = track.currentPoint

            case .Vector4:
                track.currentVector4 = previous.currentVector4
                if track.options.direction == .Forward do
                    track.fromVector4 = track.currentVector4
                else do
                    track.toVector4 = track.currentVector4

            case .Rectangle:
                track.currentRectangle = previous.currentRectangle
                if track.options.direction == .Forward do
                    track.fromRectangle = track.currentRectangle
                else do
                    track.toRectangle = track.currentRectangle
            }

            return
        }

        if track.options.direction == .Forward
        {
            let remaining = 1 - factor
            switch #complete track.kind
            {
            case .F32:
                track.currentF32 = previous.currentF32
                track.fromF32    = (track.currentF32 - factor * track.toF32) / remaining

            case .Color:
                track.currentColor = previous.currentColor
                track.fromColor    = (track.currentColor - track.toColor * factor) / remaining

            case .Point:
                track.currentPoint = previous.currentPoint
                track.fromPoint.x  = (track.currentPoint.x - factor * track.toPoint.x) / remaining
                track.fromPoint.y  = (track.currentPoint.y - factor * track.toPoint.y) / remaining

            case .Vector4:
                track.currentVector4 = previous.currentVector4
                track.fromVector4    = (track.currentVector4 - track.toVector4 * factor) / remaining

            case .Rectangle:
                track.currentRectangle     = previous.currentRectangle
                track.fromRectangle.x      = (track.currentRectangle.x - factor * track.toRectangle.x) / remaining
                track.fromRectangle.y      = (track.currentRectangle.y - factor * track.toRectangle.y) / remaining
                track.fromRectangle.width  = (track.currentRectangle.width - factor * track.toRectangle.width) / remaining
                track.fromRectangle.height = (track.currentRectangle.height - factor * track.toRectangle.height) / remaining
            }

            return
        }

        switch #complete track.kind
        {
        case .F32:
            track.currentF32 = previous.currentF32
            track.toF32      = (track.currentF32 - (1 - factor) * track.fromF32) / factor

        case .Color:
            track.currentColor = previous.currentColor
            track.toColor      = (track.currentColor - track.fromColor * (1 - factor)) / factor

        case .Point:
            track.currentPoint = previous.currentPoint
            track.toPoint.x    = (track.currentPoint.x - (1 - factor) * track.fromPoint.x) / factor
            track.toPoint.y    = (track.currentPoint.y - (1 - factor) * track.fromPoint.y) / factor

        case .Vector4:
            track.currentVector4 = previous.currentVector4
            track.toVector4      = (track.currentVector4 - track.fromVector4 * (1 - factor)) / factor

        case .Rectangle:
            track.currentRectangle   = previous.currentRectangle
            track.toRectangle.x      = (track.currentRectangle.x - (1 - factor) * track.fromRectangle.x) / factor
            track.toRectangle.y      = (track.currentRectangle.y - (1 - factor) * track.fromRectangle.y) / factor
            track.toRectangle.width  = (track.currentRectangle.width - (1 - factor) * track.fromRectangle.width) / factor
            track.toRectangle.height = (track.currentRectangle.height - (1 - factor) * track.fromRectangle.height) / factor
        }
    }

    mtd advanceRun(run: *AnimationRun, deltaSeconds: f64)->bool
    {
        var stepDelta = deltaSeconds
        while true
        {
            var hasStep       = false
            var stepDone      = true
            var stepRemainder = Swag.F64.Max
            for trackIt in run.tracks
            {
                let track = trackIt!
                if track.finished or track.step != run.currentStep do
                    continue
                hasStep              = true
                track.elapsedSeconds += stepDelta
                .applyTrack(track, progress(track))
                if isElapsed(track)
                {
                    stepRemainder = Math.min(stepRemainder, Math.max(track.elapsedSeconds - totalSeconds(track), 0))
                    .completeTrack(track, .Completed)
                }
                else do
                    stepDone = false
                if run.cancelRequested do
                    return false
            }

            if hasStep and !stepDone do
                return false

            var nextStep = Swag.U32.Max
            for track in run.tracks where !track!.finished do
                nextStep = Math.min(nextStep, track!.step)
            if nextStep == Swag.U32.Max do
                return true

            run.currentStep = nextStep
            stepDelta       = hasStep ? stepRemainder : 0
        }
    }

    mtd startTrack(track: *AnimationTrack)
    {
        let previous = .findTrack(track.target, track.channel)
        if previous and previous.kind == track.kind do
            .preserveCurrent(track, previous)
    }
}

impl Animator
{
    // Transfers a configured group to the scheduler and returns its non-owning handle.
    //
    // A group containing a detached, pending-destruction, or ordinarily hidden target is cancelled
    // without being registered and returns an invalid handle. A page retained only to paint the
    // outgoing half of [[Gui.Animator.transitionPage]] remains a valid presentation target.
    mtd start(group: #move AnimationGroup)->AnimationHandle
    {
        if group.tracks.isEmpty() do
            return {}

        for track in group.tracks
        {
            let target = track!.target
            if target.isPendingDestroy or (target.wndFlags.has(.Hidden) and !target.paintsWhenHidden) or !target.surface
            {
                for cancelledTrack in group.tracks do
                    .completeTrack(cancelledTrack!, .Cancelled)
                if group.completion do
                    group.completion(.Cancelled)
                return {}
            }
        }

        let first = group.tracks[0]!
        if !.app do
            .app = first.target.app()
        for track in group.tracks
        {
            Debug.assert(track!.target.app() == .app)
            .startTrack(track!)
        }

        // Retargeting one channel cancels its old group as one coherent operation.
        for track in group.tracks do
            .requestCancellation(track!.target, track!.channel)

        let run = Memory.new'AnimationRun()
        run.id         = .nextId
        run.tracks     = #move group.tracks
        run.completion = group.completion
        .nextId        += 1
        .animations.add(run)

        let handle  = AnimationHandle{run.id}
        let reduced = .app!.isReducedMotion()
        if reduced
        {
            for trackIt in run.tracks
            {
                let track = trackIt!
                if track.options.motion != .Decorative do
                    continue

                // Reduced motion wants the state a loop settles on, not one of its plays, so a
                // ping-pong track is collapsed to the pair that returns it to where it began.
                track.options.repeatCount = track.options.autoReverse ? 2 : 1
                track.elapsedSeconds      = totalSeconds(track)
            }
        }

        let oldDuringAdvance = .duringAdvance
        .duringAdvance = true
        let done = .advanceRun(run, 0)
        .duringAdvance = oldDuringAdvance
        if run.cancelRequested
        {
            for [index] in .animations.count where .animations[index] == run
            {
                .finishAt(index, .Cancelled)
                break
            }
        }
        elif done
        {
            for [index] in .animations.count where .animations[index] == run
            {
                .finishAt(index, .Completed)
                break
            }
        }

        return handle
    }

    // Starts one scalar track.
    mtd animateF32(target: *Wnd, channel: AnimationChannel, from, destination: f32, update: AnimationF32Update, options: AnimationOptions = {}, completion: #null AnimationCompletion = null)->AnimationHandle
    {
        var group = AnimationGroup.parallel()
        group.addF32(target, channel, from, destination, update, options, completion)
        return .start(#move group)
    }

    // Starts one color track.
    mtd animateColor(target: *Wnd, channel: AnimationChannel, from, destination: Color, update: AnimationColorUpdate, options: AnimationOptions = {}, completion: #null AnimationCompletion = null)->AnimationHandle
    {
        var group = AnimationGroup.parallel()
        group.addColor(target, channel, from, destination, update, options, completion)
        return .start(#move group)
    }

    // Starts one point track.
    mtd animatePoint(target: *Wnd, channel: AnimationChannel, from, destination: Math.Point, update: AnimationPointUpdate, options: AnimationOptions = {}, completion: #null AnimationCompletion = null)->AnimationHandle
    {
        var group = AnimationGroup.parallel()
        group.addPoint(target, channel, from, destination, update, options, completion)
        return .start(#move group)
    }

    // Starts one four-component vector track.
    mtd animateVector4(target: *Wnd, channel: AnimationChannel, from, destination: Math.Vector4, update: AnimationVector4Update, options: AnimationOptions = {}, completion: #null AnimationCompletion = null)->AnimationHandle
    {
        var group = AnimationGroup.parallel()
        group.addVector4(target, channel, from, destination, update, options, completion)
        return .start(#move group)
    }

    // Starts one rectangle track.
    mtd animateRectangle(target: *Wnd, channel: AnimationChannel, from, destination: Math.Rectangle, update: AnimationRectangleUpdate, options: AnimationOptions = {}, completion: #null AnimationCompletion = null)->AnimationHandle
    {
        var group = AnimationGroup.parallel()
        group.addRectangle(target, channel, from, destination, update, options, completion)
        return .start(#move group)
    }

    // Cancels an active animation and reports `Cancelled` to unfinished callbacks.
    mtd cancel(handle: AnimationHandle)
    {
        if !handle.isValid() do
            return
        for [index] in .animations.count
        {
            if .animations[index]!.id != handle.id do
                continue
            if .duringAdvance do
                .animations[index]!.cancelRequested = true
            else do
                .finishAt(index, .Cancelled)
            return
        }
    }

    // Reports whether a handle still names an active animation.
    mtd const isActive(handle: AnimationHandle)->bool
    {
        if !handle.isValid() do
            return false
        for run in .animations where run!.id == handle.id do
            return true
        return false
    }

    // Reports whether one target property currently has a scheduled animation.
    mtd const isActive(target: *Wnd, channel: AnimationChannel)->bool
    {
        for run in .animations
        {
            for track in run!.tracks
            {
                let value = track!
                if !value.finished and value.target == target and value.channel == channel do
                    return true
            }
        }

        return false
    }

    // Completes every active animation at its requested endpoint.
    mtd finishAll()
    {
        while .animations.count
        {
            let run = .animations[0]!
            for track in run.tracks
            {
                let value = track!
                if value.finished do
                    continue
                .applyTrack(value, restProgress(value))
                .completeTrack(value, .Completed)
            }

            .finishAt(0, .Completed)
        }
    }

    // Returns the number of groups currently owned by the scheduler.
    mtd const activeCount()->u64 => .animations.count

    internal mtd advance(deltaSeconds: f32)
    {
        .duringAdvance = true
        var index        = 0'u64
        var initialCount = .animations.count
        while index < initialCount
        {
            let run  = .animations[index]!
            let done = !run.cancelRequested and .advanceRun(run, deltaSeconds)
            if run.cancelRequested or done
            {
                .duringAdvance = false
                .finishAt(index, run.cancelRequested ? .Cancelled : .Completed)
                .duringAdvance = true
                initialCount   -= 1
                continue
            }

            index += 1
        }

        .duringAdvance = false
    }

    internal mtd cancelTarget(target: *Wnd)
    {
        .requestCancellation(target)
    }

    internal mtd cancel(target: *Wnd, channel: AnimationChannel)
    {
        .requestCancellation(target, channel)
    }

    internal mtd finishDecorative()
    {
        var index = .animations.count
        while index
        {
            index -= 1
            let run = .animations[index]!
            for track in run.tracks
            {
                let value = track!
                if value.finished or value.options.motion == .Essential do
                    continue
                .applyTrack(value, restProgress(value))
                .completeTrack(value, .Completed)
            }

            if .advanceRun(run, 0) do
                .finishAt(index, .Completed)
        }
    }

    internal mtd cancelAll()
    {
        while .animations.count do
            .finishAt(.animations.count - 1, .Cancelled)
    }

    // Replaces one visible page with another using a covered cross-fade and horizontal arrival.
    //
    // Logical visibility changes immediately, so hit testing, layout, and keyboard focus follow
    // the final page throughout the decorative transition. The outgoing page fades out under
    // the incoming page until the handoff completes, so the page area is never empty.
    // `direction` is normally `1` for forward navigation and `-1` for backward navigation.
    mtd transitionPage(outgoing: #null *Wnd, incoming: *Wnd, direction = 1'f32)->AnimationHandle
    {
        Debug.assert(incoming != null)
        if outgoing == incoming
        {
            incoming.show()
            incoming.resetPresentation()
            return {}
        }

        if outgoing and outgoing != incoming
        {
            outgoing.hide()
            outgoing.setPaintWhenHidden(true)
        }

        incoming.show()
        if incoming.parent do
            incoming.parent.applyLayout()

        let metrics = incoming.themeMetrics()
        let offset  = Math.Point{metrics.motion_PageOffset * (direction < 0 ? -1 : 1), 0}
        incoming.setPresentationOpacity(0)
        incoming.setPresentationOffset(offset)

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(metrics.motion_PageSeconds)
        options.easing   = .EaseOut

        var group = AnimationGroup.parallel()
        if outgoing do
            group.addF32(outgoing, AnimationChannel.from("Gui.Page.Opacity"), 1, 0, func(wnd, value) { wnd.setPresentationOpacity(value); }, options)
        group.addF32(incoming, AnimationChannel.from("Gui.Page.Opacity"), 0, 1, func(wnd, value) { wnd.setPresentationOpacity(value); }, options)
        group.addPoint(incoming, AnimationChannel.from("Gui.Page.Offset"), offset, {}, func(wnd, value) { wnd.setPresentationOffset(value); }, options)
        group.setCompletion(func|outgoing, incoming|(result)
        {
            discard result
            if outgoing
            {
                let wnd = outgoing!
                if !wnd.isPendingDestroy
                {
                    wnd.resetPresentation()
                    wnd.setPaintWhenHidden(false)
                }
            }

            if !incoming.isPendingDestroy do
                incoming.resetPresentation()
        })
        return .start(#move group)
    }

    // Animates one layout-managed window to a new preferred height.
    mtd animateLayoutHeight(target: *Wnd, height: f32)->AnimationHandle
    {
        Debug.assert(target != null)
        Debug.assert(height >= 0)
        let from = target.position.height
        if from == height
        {
            target.preferredSize.y = height
            return {}
        }

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(target.themeMetrics().motion_PanelSeconds)
        options.easing   = .EaseInOut
        options.impact   = .Layout

        return .animateF32(target,
                           AnimationChannel.from("Gui.Layout.Height"),
                           from,
                           height,
                           func(wnd, value)
                           {
                               wnd.resize(wnd.position.width, value, false)
                           },
                           options,
                           func|target, height|(result)
                           {
                               if target.isPendingDestroy do
                                   return
                               target.preferredSize.y = result == .Completed ? height : target.position.height
                               target.invalidateLayout()
                               if target.parent do
                                   target.parent!.applyLayout()
                           })
    }
}
