// GUI11 - finite animation laboratory.
//
// The page switch uses the widget-level transition. The two demonstrations below use the same
// application animator directly, once in parallel and once as a sequence. Toggle reduced motion
// to verify that decorative movement completes immediately without changing final state.

using Core, Gui

const TestFrames = 120

var app: Application

var g_ParallelTarget:  #null *PushButton
var g_SequenceTargetA: #null *PushButton
var g_SequenceTargetB: #null *PushButton

func motionOptions(duration: Time.Duration = 420'ms)->AnimationOptions
{
    var result: retval
    result.duration = duration
    result.easing   = .EaseOut
    return result
}

func setOpacity(wnd: *Wnd, value: f32)
{
    wnd.setPresentationOpacity(value)
}

func setOffset(wnd: *Wnd, value: Math.Point)
{
    wnd.setPresentationOffset(value)
}

func resetPresentation(result: AnimationResult, wnd: *Wnd)
{
    discard result
    if !wnd.isPendingDestroy do
        wnd.resetPresentation()
}

func playParallel()
{
    let target = g_ParallelTarget!
    target.setPresentationOpacity(0.15)
    target.setPresentationOffset({-120, 0})

    var group   = AnimationGroup.parallel()
    let options = motionOptions()
    group.addF32(target, AnimationChannel.from("Gui11.Parallel.Opacity"), 0.15, 1, &setOpacity, options)
    group.addPoint(target, AnimationChannel.from("Gui11.Parallel.Offset"), {-120, 0}, {}, &setOffset, options)
    group.setCompletion(func|target|(result) { resetPresentation(result, target); })
    discard app.animator.start(#move group)
}

func playSequence()
{
    let first  = g_SequenceTargetA!
    let second = g_SequenceTargetB!
    first.setPresentationOffset({-90, 0})
    second.setPresentationOffset({-90, 0})

    var group   = AnimationGroup.sequence()
    let options = motionOptions(280'ms)
    group.addPoint(first, AnimationChannel.from("Gui11.Sequence.First"), {-90, 0}, {}, &setOffset, options, func|first|(result) { resetPresentation(result, first); })
    group.addPoint(second, AnimationChannel.from("Gui11.Sequence.Second"), {-90, 0}, {}, &setOffset, options, func|second|(result) { resetPresentation(result, second); })
    discard app.animator.start(#move group)
}

func createPage(parent: *Wnd, title, explanation: string)->*Wnd
{
    let page = Wnd.create'Wnd(parent)
    page.backgroundStyle = .View

    let titleLabel = Label.create(page, title, {32, 34, 760, 44})
    titleLabel.style.setFont(page.theme().createDefaultFont(25), .Regular)
    titleLabel.setTextAlignment(.Left, .Center)

    let explanationLabel = Label.create(page, explanation, {32, 82, 760, 58}, null, .WordWrap | .SecondaryText)
    explanationLabel.setTextAlignment(.Left, .Top)

    return page
}

func buildParallelPage(parent: *Wnd)->*Wnd
{
    let page = createPage(parent, "Parallel group", "Opacity and horizontal offset share one timeline. Press Replay while it moves to see a clean retarget from the visible value.")
    g_ParallelTarget = PushButton.create(page, "One target, two typed tracks", {250, 215, 340, 64})
    let replay = PushButton.create(page, "Replay parallel", {340, 330, 160, 38})
    replay.sigPressed += func(btn)
    {
        discard btn
        playParallel()
    }
    return page
}

func buildSequencePage(parent: *Wnd)->*Wnd
{
    let page = createPage(parent, "Sequence group", "The second track waits for the first one. Both use the same easing and keep their logical hit boxes fixed while they arrive.")
    g_SequenceTargetA = PushButton.create(page, "First", {190, 215, 190, 64})
    g_SequenceTargetB = PushButton.create(page, "Then", {460, 215, 190, 64})
    let replay = PushButton.create(page, "Replay sequence", {340, 330, 160, 38})
    replay.sigPressed += func(btn)
    {
        discard btn
        playSequence()
    }
    return page
}

#main
{
    let flags   = SurfaceFlags.LargeCaption | SurfaceFlags.MinimizeButton | SurfaceFlags.CloseButton | SurfaceFlags.Border
    let surface = (try app.createSurface(120, 70, 920, 620, flags))!
    app.theme.setSwagDark()
    app.notifyThemeChanged()
    surface.setTitle("GUI11 animation laboratory")
    surface.setIcon(app.theme.icon(.Play, 18))

    let view = surface.view()
    view.backgroundStyle = .View
    Separator.create(view, .Top, .Accent)

    let tabs = Tab.create(view)
    tabs.dockStyle = .Center
    tabs.margin    = {32, 72, 32, 32}
    tabs.setForm(.Button)
    tabs.setPageTransitions(true)
    tabs.addItem("Parallel", view: buildParallelPage(tabs))
    tabs.addItem("Sequence", view: buildSequencePage(tabs))

    let reduced = CheckButton.create(view, "Reduced motion", {32, 24, 180, 34})
    reduced.sigChanged += func(box)
    {
        app.setMotionPreference(box.state == .Checked ? .Reduced : .Full)
    }

    let hint = Label.create(view, "Switch pages to inspect the standard page transition.", {230, 24, 650, 34}, null, .SecondaryText)
    hint.setTextAlignment(.Right, .Center)

    if Env.isSmokeRun() do
        app.maxRunFrame = TestFrames

    view.applyLayout()
    surface.show()
    playParallel()
    app.run()
}
