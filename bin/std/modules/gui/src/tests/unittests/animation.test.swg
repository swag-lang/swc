#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

var AnimationTestF32:       f32
var AnimationTestF32B:      f32
var AnimationTestPoint:     Math.Point
var AnimationTestVector:    Math.Vector4
var AnimationTestRectangle: Math.Rectangle
var AnimationTestColor:     Math.Vector4
var AnimationTestResult:    AnimationResult
var AnimationTestCompleted: u32

func animationSetF32(wnd: *Wnd, value: f32)
{
    discard wnd
    AnimationTestF32 = value
}

func animationSetF32B(wnd: *Wnd, value: f32)
{
    discard wnd
    AnimationTestF32B = value
}

func animationSetPoint(wnd: *Wnd, value: Math.Point)
{
    discard wnd
    AnimationTestPoint = value
}

func animationSetVector(wnd: *Wnd, value: Math.Vector4)
{
    discard wnd
    AnimationTestVector = value
}

func animationSetRectangle(wnd: *Wnd, value: Math.Rectangle)
{
    discard wnd
    AnimationTestRectangle = value
}

func animationSetColor(wnd: *Wnd, value: Color)
{
    discard wnd
    AnimationTestColor = value.toVector4()
}

func animationCompleted(result: AnimationResult)
{
    AnimationTestResult    = result
    AnimationTestCompleted += 1
}

func linearSecond()->AnimationOptions
{
    var result: retval
    result.duration = 1000'ms
    result.easing   = .Linear
    return result
}

// Typed parallel tracks sample deterministically at 0, 50, and 100 percent.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200, 1.5)
    defer host.shutdown()
    host.setReducedMotion(false)

    let target  = Wnd.create'Wnd(&host.root)
    let options = linearSecond()
    AnimationTestCompleted = 0
    var group = AnimationGroup.parallel()
    group.addF32(target, AnimationChannel.from("test.scalar"), 0, 10, &animationSetF32, options)
    group.addColor(target, AnimationChannel.from("test.color"), Argb.Black, Argb.White, &animationSetColor, options)
    group.addPoint(target, AnimationChannel.from("test.point"), {}, {10, 20}, &animationSetPoint, options)
    group.addVector4(target, AnimationChannel.from("test.vector"), {}, {2, 4, 6, 8}, &animationSetVector, options)
    group.addRectangle(target, AnimationChannel.from("test.rectangle"), {}, {10, 20, 30, 40}, &animationSetRectangle, options)
    group.setCompletion(&animationCompleted)
    let handle = host.app.animator.start(#move group)

    @assert(handle.isValid() and host.app.animator.isActive(handle))
    @assert(AnimationTestF32 == 0 and AnimationTestPoint == Math.Point{})

    host.advanceAnimations(0.5)
    @assert(Math.isEqualEpsilon(AnimationTestF32, 5, 0.001))
    @assert(AnimationTestPoint == Math.Point{5, 10})
    @assert(AnimationTestVector == Math.Vector4{1, 2, 3, 4})
    @assert(AnimationTestRectangle == Math.Rectangle{5, 10, 15, 20})
    @assert(Math.isEqualEpsilon(AnimationTestColor.x, 0.5, 0.01))

    host.advanceAnimations(0.5)
    @assert(AnimationTestF32 == 10 and AnimationTestPoint == Math.Point{10, 20})
    @assert(!host.app.animator.isActive(handle) and host.app.animator.activeCount() == 0)
    @assert(AnimationTestCompleted == 1 and AnimationTestResult == .Completed)
    @assert(host.app.frameEvents.isEmpty())
    discard host.render()
}

// Delay, easing, and reverse direction share the same normalized clock.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()
    host.setReducedMotion(false)

    let target = Wnd.create'Wnd(&host.root)
    var options: AnimationOptions
    options.delay    = 250'ms
    options.duration = 1000'ms
    options.easing   = .EaseIn
    discard host.app.animator.animateF32(target, AnimationChannel.from("test.easing"), 0, 8, &animationSetF32, options)
    host.advanceAnimations(0.25)
    @assert(AnimationTestF32 == 0)
    host.advanceAnimations(0.5)
    @assert(Math.isEqualEpsilon(AnimationTestF32, 1, 0.001))
    host.finishAnimations()
    @assert(AnimationTestF32 == 8)

    options.delay     = {}
    options.direction = .Reverse
    discard host.app.animator.animateF32(target, AnimationChannel.from("test.reverse"), 2, 10, &animationSetF32, options)
    @assert(AnimationTestF32 == 10)
    host.finishAnimations()
    @assert(AnimationTestF32 == 2)
}

// Retargeting begins at the on-screen value rather than the new authored source.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()
    host.setReducedMotion(false)

    let target  = Wnd.create'Wnd(&host.root)
    let channel = AnimationChannel.from("test.retarget")
    let options = linearSecond()
    discard host.app.animator.animateF32(target, channel, 0, 100, &animationSetF32, options)
    host.advanceAnimations(0.25)
    @assert(AnimationTestF32 == 25)

    discard host.app.animator.animateF32(target, channel, 0, 200, &animationSetF32, options)
    @assert(AnimationTestF32 == 25)
    host.advanceAnimations(0.5)
    @assert(Math.isEqualEpsilon(AnimationTestF32, 112.5, 0.001))
}

// Parallel and sequence groups have distinct advancement contracts.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()
    host.setReducedMotion(false)

    let first   = Wnd.create'Wnd(&host.root)
    let second  = Wnd.create'Wnd(&host.root)
    let options = linearSecond()
    AnimationTestF32B = -1

    var sequence = AnimationGroup.sequence()
    sequence.addF32(first, AnimationChannel.from("test.sequence.first"), 0, 10, &animationSetF32, options)
    sequence.addF32(second, AnimationChannel.from("test.sequence.second"), 0, 20, &animationSetF32B, options)
    discard host.app.animator.start(#move sequence)
    host.advanceAnimations(1)
    @assert(AnimationTestF32 == 10 and AnimationTestF32B == 0)
    host.advanceAnimations(0.5)
    @assert(AnimationTestF32B == 10)
    host.finishAnimations()
    @assert(AnimationTestF32B == 20)

    AnimationTestF32, AnimationTestF32B = -1
    sequence = AnimationGroup.sequence()
    sequence.addF32(first, AnimationChannel.from("test.sequence.overflow.first"), 0, 10, &animationSetF32, options)
    sequence.addF32(second, AnimationChannel.from("test.sequence.overflow.second"), 0, 20, &animationSetF32B, options)
    discard host.app.animator.start(#move sequence)
    host.advanceAnimations(1.5)
    @assert(AnimationTestF32 == 10 and AnimationTestF32B == 10)
}

// Hiding or destroying a target cancels its tracks and reports cancellation once.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()
    host.setReducedMotion(false)
    AnimationTestCompleted = 0

    let target = Wnd.create'Wnd(&host.root)
    let handle = host.app.animator.animateF32(target, AnimationChannel.from("test.lifetime"), 0, 10, &animationSetF32, linearSecond(), &animationCompleted)
    target.hide()
    @assert(!host.app.animator.isActive(handle))
    @assert(AnimationTestCompleted == 1 and AnimationTestResult == .Cancelled)

    target.show()
    discard host.app.animator.animateF32(target, AnimationChannel.from("test.destroy"), 0, 10, &animationSetF32, linearSecond(), &animationCompleted)
    target.destroy()
    @assert(host.app.animator.activeCount() == 0)
    @assert(AnimationTestCompleted == 2 and AnimationTestResult == .Cancelled)
}

// Reduced motion completes decoration immediately but leaves essential feedback on the clock.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()
    let target = Wnd.create'Wnd(&host.root)

    discard host.app.animator.animateF32(target, AnimationChannel.from("test.reduced"), 0, 10, &animationSetF32, linearSecond())
    @assert(AnimationTestF32 == 10 and host.app.animator.activeCount() == 0)

    var options = linearSecond()
    options.motion = .Essential
    let handle = host.app.animator.animateF32(target, AnimationChannel.from("test.essential"), 0, 10, &animationSetF32, options)
    @assert(host.app.animator.isActive(handle) and AnimationTestF32 == 0)
    host.finishAnimations()
}

// A cancelled color blend can resume from its visible value after the target is shown again.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()
    host.setReducedMotion(false)
    let target = Wnd.create'Wnd(&host.root)

    var blend: BlendColor
    blend.apply(target, Argb.Black)
    blend.apply(target, Argb.White)
    host.advanceAnimations(0.05)
    let interrupted = blend.cur()
    @assert(interrupted != Color.fromArgb(Argb.Black) and interrupted != Color.fromArgb(Argb.White))

    target.hide()
    @assert(host.app.animator.activeCount() == 0)
    target.show()
    blend.apply(target, Argb.White)
    @assert(host.app.animator.activeCount() == 1)
    host.finishAnimations()
    @assert(blend.cur() == Color.fromArgb(Argb.White))
}

// Theme and DPI changes do not detach a live track from its target or reset its progress.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()
    host.setReducedMotion(false)
    let target  = Wnd.create'Wnd(&host.root)
    let channel = AnimationChannel.from("test.environment")

    discard host.app.animator.animatePoint(target, channel, {}, {100, 50}, &animationSetPoint, linearSecond())
    host.advanceAnimations(0.3)
    let before = AnimationTestPoint
    host.surface.setDpiScaleRaw(1.75)
    host.notify(.ThemeChanged)
    @assert(host.app.animator.isActive(target, channel))
    @assert(AnimationTestPoint == before)
    host.advanceAnimations(0.7)
    @assert(AnimationTestPoint == Math.Point{100, 50})
}

// Every curve starts at zero and lands on one; only the named ones leave the interval.
#test
{
    for curve in [AnimationEasing.Linear, .EaseIn, .EaseOut, .EaseInOut, .EaseInBack, .EaseOutBack, .EaseInOutBack, .EaseOutElastic, .EaseOutBounce]
    {
        var easing = curve
        @assert(Math.isEqualEpsilon(easing.evaluate(0), 0, 0.001))
        @assert(Math.isEqualEpsilon(easing.evaluate(1), 1, 0.001))

        // Progress outside the interval is clamped, never extrapolated.
        @assert(easing.evaluate(-3) == easing.evaluate(0))
        @assert(easing.evaluate(4) == easing.evaluate(1))
    }

    var linear = AnimationEasing.Linear
    @assert(Math.isEqualEpsilon(linear.evaluate(0.25), 0.25, 0.001))

    // An overshooting curve is chosen for exactly that: it leaves the interval and comes back.
    var back = AnimationEasing.EaseOutBack
    @assert(back.evaluate(0.7) > 1)

    var anticipate = AnimationEasing.EaseInBack
    @assert(anticipate.evaluate(0.3) < 0)

    // A bounce lands and rebounds without ever passing its endpoint.
    var bounce = AnimationEasing.EaseOutBounce
    for [step] in 21
    {
        let value = bounce.evaluate(cast(f32) step / 20)
        @assert(value >= 0 and value <= 1.001)
    }
}

// A repeating track replays its curve and holds the endpoint of its last play.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()
    host.setReducedMotion(false)

    let target  = Wnd.create'Wnd(&host.root)
    var options = linearSecond()
    options.repeatCount    = 3
    AnimationTestCompleted = 0
    let handle = host.app.animator.animateF32(target, AnimationChannel.from("test.repeat"), 0, 10, &animationSetF32, options, &animationCompleted)

    host.advanceAnimations(0.5)
    @assert(AnimationTestF32 == 5)

    // Each play restarts the curve instead of continuing past its end value.
    host.advanceAnimations(1)
    @assert(AnimationTestF32 == 5 and host.app.animator.isActive(handle))
    host.advanceAnimations(1)
    @assert(AnimationTestF32 == 5)

    host.advanceAnimations(0.5)
    @assert(AnimationTestF32 == 10)
    @assert(!host.app.animator.isActive(handle))
    @assert(AnimationTestCompleted == 1 and AnimationTestResult == .Completed)
}

// A ping-pong track runs its odd plays backwards and settles where it started.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()
    host.setReducedMotion(false)

    let target  = Wnd.create'Wnd(&host.root)
    var options = linearSecond()
    options.repeatCount = 2
    options.autoReverse = true
    let handle = host.app.animator.animateF32(target, AnimationChannel.from("test.pingpong"), 0, 10, &animationSetF32, options)

    host.advanceAnimations(0.75)
    @assert(Math.isEqualEpsilon(AnimationTestF32, 7.5, 0.001))
    host.advanceAnimations(0.5)
    @assert(Math.isEqualEpsilon(AnimationTestF32, 7.5, 0.001))
    host.advanceAnimations(0.5)
    @assert(Math.isEqualEpsilon(AnimationTestF32, 2.5, 0.001))

    host.advanceAnimations(0.25)
    @assert(AnimationTestF32 == 0 and !host.app.animator.isActive(handle))
}

// An endless track never completes on its own, and finishes on its resting value.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()
    host.setReducedMotion(false)

    let target  = Wnd.create'Wnd(&host.root)
    var options = linearSecond()
    options.repeatCount = 0
    let forward = host.app.animator.animateF32(target, AnimationChannel.from("test.endless"), 0, 10, &animationSetF32, options)

    host.advanceAnimations(6.5)
    @assert(AnimationTestF32 == 5 and host.app.animator.isActive(forward))
    host.finishAnimations()
    @assert(AnimationTestF32 == 10 and !host.app.animator.isActive(forward))

    // A ping-pong loop rests at the value it keeps returning to, which is where it began.
    options.autoReverse = true
    discard host.app.animator.animateF32(target, AnimationChannel.from("test.endless.pingpong"), 2, 8, &animationSetF32, options)
    host.advanceAnimations(3.5)
    @assert(AnimationTestF32 == 5)
    host.finishAnimations()
    @assert(AnimationTestF32 == 2)
}

// Reduced motion collapses a decorative loop instead of leaving it running forever.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()

    let target  = Wnd.create'Wnd(&host.root)
    var options = linearSecond()
    options.repeatCount = 0
    options.autoReverse = true
    discard host.app.animator.animateF32(target, AnimationChannel.from("test.reduced.loop"), 3, 9, &animationSetF32, options)
    @assert(AnimationTestF32 == 3 and host.app.animator.activeCount() == 0)

    // An essential loop still reports, because reduced motion is about decoration.
    options.motion = .Essential
    let handle = host.app.animator.animateF32(target, AnimationChannel.from("test.reduced.essential"), 3, 9, &animationSetF32, options)
    host.advanceAnimations(0.5)
    @assert(AnimationTestF32 == 6 and host.app.animator.isActive(handle))
    host.finishAnimations()
}

// Presentation scale moves the painted rectangle around its pivot and leaves layout alone.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    host.setReducedMotion(false)

    let target = Wnd.create'Wnd(&host.root, {40, 20, 100, 50})
    @assert(target.presentationRect() == Math.Rectangle{40, 20, 100, 50})

    target.setPresentationScale({0.5, 0.5})
    @assert(target.presentationRect() == Math.Rectangle{65, 32.5, 50, 25})
    @assert(target.position == Math.Rectangle{40, 20, 100, 50})

    // A corner pivot keeps that corner still.
    target.setPresentationPivot({})
    @assert(target.presentationRect() == Math.Rectangle{40, 20, 50, 25})

    target.setPresentationOffset({10, -4})
    @assert(target.presentationRect() == Math.Rectangle{50, 16, 50, 25})

    target.resetPresentation()
    @assert(target.presentationRect() == Math.Rectangle{40, 20, 100, 50})
    @assert(target.presentationScale == Math.Point{1, 1} and target.presentationPivot == Math.Point{0.5, 0.5})

    // The same state, driven through the scheduler.
    discard host.app.animator.animateF32(target, AnimationChannel.from("test.scale"), 1, 2, func(wnd, value) { wnd.setPresentationScale({value, value}); }, linearSecond())
    host.advanceAnimations(0.5)
    @assert(target.presentationScale == Math.Point{1.5, 1.5})
    @assert(target.presentationRect() == Math.Rectangle{15, 7.5, 150, 75})
    host.finishAnimations()
    @assert(target.presentationScale == Math.Point{2, 2})
    discard host.render()
}
