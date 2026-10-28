// GUI11 - the motion laboratory.
//
// The other GUI examples show what the toolkit can build; this one shows how it moves. Four pages,
// one per question a motion system has to answer: what shape does a value travel along, how do
// several values agree on one arrival, what happens when the reader interrupts, and what is left
// when the reader has asked for no motion at all.
//
// Everything here goes through [[Gui.Animator]]. Nothing is driven from a frame callback, nothing
// keeps its own clock, and no page moves a window by changing its layout rectangle: decoration
// travels on presentation opacity, offset, and scale, so hit testing and focus never chase it.

using Core, Gui, Pixel

const W = 1240
const H = 860

// The page keeps reading margins at its sides; the header stands under the window strip.
const PageMargin   = 48.0
const TitleSize    = 34'u32
const BarHeight    = 34.0
const ReducedWidth = 190.0
const PagePad      = 18.0
const NoteHeight   = 38.0
const RowGap       = 12.0
const PanelHeight  = 146.0
const CaptionGap   = 22.0
const MaxCardH     = 176.0

const SmokeFramesPerPage = 40

var app: Application

var g_Surface:    *Surface?
var g_View:       *Wnd?
var g_Title:      *Label?
var g_SubTitle:   *Label?
var g_Hint:       *HintLine?
var g_Lens:       *Lens.View?
var g_Appearance: *AppearanceButton?
var g_Reduced:    *CheckButton?
var g_Tabs:       *Tab?

var g_Light:      bool
var g_SmokeFrame: u32

// Curves page.
var g_CurvePage: *Wnd?
var g_CurveNote: *Label?
var g_Wall:      *CurveWall?

// Choreography page.
var g_StagePage:     *Wnd?
var g_StageNote:     *Label?
var g_StageControls: *PanelWnd?
var g_StageEasing:   *ComboBox?
var g_StageDuration: *Slider?
var g_StageStagger:  *Slider?
var g_StageReadout:  *Label?
var g_StageReplay:   *PushButton?
var g_StageHint:     *Label?
var g_StageCaptions: Array'(*Label)
var g_Cards:         Array'(*MotionCard)

// Interruption page.
var g_FieldPage:     *Wnd?
var g_FieldNote:     *Label?
var g_FieldControls: *PanelWnd?
var g_FieldEasing:   *ComboBox?
var g_FieldDuration: *Slider?
var g_FieldReadout:  *Label?
var g_FieldPreserve: *CheckButton?
var g_FieldClear:    *PushButton?
var g_FieldCaption:  *Label?
var g_Field:         *MotionField?

// Preference page.
var g_PrefPage:       *Wnd?
var g_PrefNote:       *Label?
var g_Decorative:     *PanelWnd?
var g_DecorativeBtn:  *PushButton?
var g_DecorativeNote: *Label?
var g_Essential:      *PanelWnd?
var g_EssentialLbl:   *Label?
var g_EssentialNote:  *Label?
var g_Expander:       *PanelWnd?
var g_ExpandBtn:      *PushButton?
var g_ExpandHost:     *Wnd?
var g_Detail:         *Wnd?
var g_DetailText:     *Label?
var g_Expanded:       bool

const StageCardCount = 6

const StageTitles = ["Group", "Stagger", "Curve", "Scale", "Fade", "Rise"]

const StageDetails = ["one start", "per index", "one shape", "0.86 to 1", "0 to 1", "42 to 0"]

const CollapsedDetail = 1.0
const ExpandedDetail  = 132.0

//////////////////////////////////////////////
// Motion preference
//////////////////////////////////////////////

// Restarts every endless track of the example.
//
// A loop is decorative or essential, and reduced motion ends the decorative ones for good rather
// than pausing them, so leaving the preference re-arms them here instead of resuming anything.
func restartLoops()
{
    g_Wall!.startClock()
    startDecorativePulse()
    startEssentialBreath()
}

func onReducedChanged(box: *CheckButton)
{
    app.setMotionPreference(box.state == .Checked ? .Reduced : .Full)
    restartLoops()
    updateHint()
}

func toggleReduced()
{
    let box = unwrap g_Reduced
    box.setState(box.state == .Checked ? .Unchecked : .Checked)
    onReducedChanged(box)
}

// Teaches the lens, and says in a few words what the motion preference leaves running.
func updateHint()
{
    let hint = unwrap g_Hint
    hint.clearHints()
    hint.addHint("Ctrl K", "pages, motion, appearance")
    hint.addHint("", app.isReducedMotion() ? "reduced motion: decorative tracks rest, essential ones keep reporting" : "every track runs on the application frame clock")
}

//////////////////////////////////////////////
// Curves page
//////////////////////////////////////////////

func buildCurvePage(parent: *Wnd)->*Wnd
{
    let page = Wnd.create'Wnd(parent)
    page.backgroundStyle = .Transparent
    g_CurvePage = page

    g_CurveNote = Label.create(page, "Nine curves, one clock. The dot on the graph and the puck under it are the same number: the shape is the movement. The clock repeats forever and reverses on every play, which is one track, not a frame callback.", {}, null, .WordWrap | .SecondaryText)
    g_Wall      = CurveWall.create(page)

    page.hookOnEvent = &onCurvePageEvent
    return page
}

func layoutCurvePage()
{
    let page = g_CurvePage
    if not page do
        return

    let rect  = page.clientRect()
    let width = Math.max(rect.width - 2 * PagePad, 1.0)
    g_CurveNote!.setPosition(Math.Rectangle{PagePad, PagePad, width, NoteHeight})
    let wallHeight = Math.max(rect.height - 2 * PagePad - NoteHeight - RowGap, 1.0)
    g_Wall!.setPosition(Math.Rectangle{PagePad, PagePad + NoteHeight + RowGap, width, wallHeight})
}

func onCurvePageEvent(_: *Wnd, evt: IEvent)->bool
{
    if evt is ResizeEvent do
        layoutCurvePage()
    return false
}

//////////////////////////////////////////////
// Choreography page
//////////////////////////////////////////////

func setCardOpacity(wnd: *Wnd, value: f32)
{
    wnd.setPresentationOpacity(value)
}

func setCardOffset(wnd: *Wnd, value: Math.Point)
{
    wnd.setPresentationOffset(value)
}

func setCardScale(wnd: *Wnd, value: f32)
{
    wnd.setPresentationScale(Math.Point{value, value})
}

func buildStagePage(parent: *Wnd)->*Wnd
{
    let page = Wnd.create'Wnd(parent)
    page.backgroundStyle = .Transparent
    g_StagePage = page

    g_StageNote = Label.create(page, "Six tiles, one parallel group, eighteen tracks. Each tile fades, rises, and grows on the same timeline, offset by its rank. Nothing below moves: presentation state never touches a layout rectangle.", {}, null, .WordWrap | .SecondaryText)

    let controls = PanelWnd.create(page, "Timeline")
    g_StageControls = controls

    for caption in ["Curve", "Duration", "Stagger"] do
        g_StageCaptions.add(Label.create(controls, caption, {}, null, .SecondaryText))

    let easing = ComboBox.create(controls)
    g_StageEasing = easing
    for index in WallCurves.count do
        discard easing.addItem(curveName(WallCurves[index]))
    easing.setSelectedIndex(5, false)
    easing.sigChanged += func(_, _)
    {
        playEntrance()
    }

    let duration = Slider.create(controls)
    g_StageDuration = duration
    duration.setBounds(120, 1400)
    duration.setValue(560)
    duration.sigChanged += &onStageSlider

    let stagger = Slider.create(controls)
    g_StageStagger = stagger
    stagger.setBounds(0, 220)
    stagger.setValue(70)
    stagger.sigChanged += &onStageSlider

    g_StageReadout = Label.create(controls, "", {}, null, .SecondaryText)

    let replay = PushButton.create(controls, "Replay", {}, null, .Strong)
    g_StageReplay     = replay
    replay.sigPressed += func(_)
    {
        playEntrance()
    }

    for index in StageCardCount do
        g_Cards.add(MotionCard.create(page, cast(s32, index) + 1, StageTitles[index], StageDetails[index]))

    g_StageHint = Label.create(page, "Press Replay while the strip is still arriving: each tile keeps the value it is showing and continues from there.", {}, null, .SecondaryText)

    updateStageReadout()
    page.hookOnEvent = &onStagePageEvent
    return page
}

func onStageSlider(_: *Slider)
{
    updateStageReadout()
    playEntrance()
}

func updateStageReadout()
{
    let duration = g_StageDuration!.value()
    let stagger  = g_StageStagger!.value()
    let last     = duration + stagger * cast(f32, (StageCardCount - 1))
    g_StageReadout!.setText(Format.toString("% ms each, % ms apart, % ms until the last tile lands",
                                            cast(s32, duration),
                                            cast(s32, stagger),
                                            cast(s32, last)))
}

// Replays the whole entrance from wherever the tiles currently are.
//
// Pressing Replay while the strip is still arriving is the interesting case: the group replaces
// the running one channel by channel, so every tile continues from the value on screen instead of
// snapping back to the start of the timeline.
func playEntrance()
{
    let curve    = WallCurves[g_StageEasing!.selectedIndex]
    let duration = Time.Duration.fromSeconds(cast(f64, g_StageDuration!.value()) / 1000)
    let stagger  = cast(f64, g_StageStagger!.value()) / 1000

    var group = AnimationGroup.concurrent()
    for card, index in g_Cards
    {
        let wnd   = card
        let delay = Time.Duration.fromSeconds(stagger * cast(f64, index))

        var motion: AnimationOptions
        motion.delay    = delay
        motion.duration = duration
        motion.easing   = curve

        // Opacity gets a curve of its own: an overshooting shape reads as weight on a position,
        // and as nothing at all on a value the compositor clamps anyway.
        var fade: AnimationOptions
        fade.delay    = delay
        fade.duration = duration
        fade.easing   = .EaseOut

        group.addF32(wnd, AnimationChannel.from("Gui11.Stage.Opacity"), 0, 1, &setCardOpacity, fade)
        group.addPoint(wnd, AnimationChannel.from("Gui11.Stage.Offset"), {0, 42}, {}, &setCardOffset, motion)
        group.addF32(wnd, AnimationChannel.from("Gui11.Stage.Scale"), 0.86, 1, &setCardScale, motion)
    }

    group.setCompletion(&onEntranceEnded)
    discard app.animator.start(#move group)
}

func onEntranceEnded(_: AnimationResult)
{
    // Presentation state is dropped once it is back at rest, so a settled tile costs the painter
    // nothing: no layer, no resample, no per-frame composition.
    for card in g_Cards
    {
        if not card.isPendingDestroy do
            card.resetPresentation()
    }
}

func layoutStagePage()
{
    let page = g_StagePage
    if not page do
        return

    let rect  = page.clientRect()
    let width = Math.max(rect.width - 2 * PagePad, 1.0)
    g_StageNote!.setPosition(Math.Rectangle{PagePad, PagePad, width, NoteHeight})

    let controlsY = PagePad + NoteHeight + RowGap
    let controls  = unwrap g_StageControls
    controls.setPosition(Math.Rectangle{PagePad, controlsY, width, PanelHeight})

    let inner   = controls.contentRect()
    let rowY    = inner.y + CaptionGap
    let columns = [168.0, 190.0, 190.0]
    var x       = inner.x
    for caption, index in g_StageCaptions
    {
        caption.setPosition(Math.Rectangle{x, inner.y, columns[index], 20})
        x += columns[index] + 16
    }

    x = inner.x
    g_StageEasing!.setPosition(Math.Rectangle{x, rowY, columns[0], BarHeight})
    x += columns[0] + 16
    g_StageDuration!.setPosition(Math.Rectangle{x, rowY, columns[1], BarHeight})
    x += columns[1] + 16
    g_StageStagger!.setPosition(Math.Rectangle{x, rowY, columns[2], BarHeight})
    g_StageReplay!.setPosition(Math.Rectangle{inner.right() - 120, rowY, 120, BarHeight})
    g_StageReadout!.setPosition(Math.Rectangle{inner.x, rowY + BarHeight + 8, inner.width, 22})

    let stripY = controlsY + PanelHeight + RowGap
    let cardH  = Math.clamp(rect.height - stripY - PagePad - 30, 90.0, MaxCardH)
    let cardW  = (width - cast(f32, (StageCardCount - 1)) * RowGap) / cast(f32, StageCardCount)

    for card, index in g_Cards do
        card.setPosition(Math.Rectangle{PagePad + cast(f32, index) * (cardW + RowGap), stripY, cardW, cardH})
    g_StageHint!.setPosition(Math.Rectangle{PagePad, stripY + cardH + 10, width, 22})
}

func onStagePageEvent(_: *Wnd, evt: IEvent)->bool
{
    if evt is ResizeEvent do
        layoutStagePage()
    return false
}

//////////////////////////////////////////////
// Interruption page
//////////////////////////////////////////////

func buildFieldPage(parent: *Wnd)->*Wnd
{
    let page = Wnd.create'Wnd(parent)
    page.backgroundStyle = .Transparent
    g_FieldPage = page

    g_FieldNote = Label.create(page, "One channel owns the puck. Clicking again while it travels does not stack a second animation: it replaces the first one from the value on screen, which is why the trail bends instead of jumping.", {}, null, .WordWrap | .SecondaryText)

    let controls = PanelWnd.create(page, "Track")
    g_FieldControls = controls

    g_FieldCaption = Label.create(controls, "Curve, duration, and how a replacement treats the run it interrupts", {}, null, .SecondaryText)

    let easing = ComboBox.create(controls)
    g_FieldEasing = easing
    for index in WallCurves.count do
        discard easing.addItem(curveName(WallCurves[index]))
    easing.setSelectedIndex(2, false)
    easing.sigChanged += func(_, index)
    {
        g_Field!.easing = WallCurves[index]
    }

    let duration = Slider.create(controls)
    g_FieldDuration = duration
    duration.setBounds(200, 2000)
    duration.setValue(900)
    duration.sigChanged += func(slider)
    {
        g_Field!.travelTime = Time.Duration.fromSeconds(cast(f64, slider.value()) / 1000)
        updateFieldReadout()
    }

    g_FieldReadout = Label.create(controls, "", {}, null, .SecondaryText)

    let preserve = CheckButton.create(controls, "Keep progress on replacement")
    g_FieldPreserve     = preserve
    preserve.sigChanged += func(box)
    {
        g_Field!.preserveProgress = box.state == .Checked
    }

    let clear = PushButton.create(controls, "Clear trail")
    g_FieldClear     = clear
    clear.sigPressed += func(_)
    {
        g_Field!.clearTrail()
        g_Field!.invalidate()
    }

    g_Field = MotionField.create(page)
    updateFieldReadout()

    page.hookOnEvent = &onFieldPageEvent
    return page
}

func updateFieldReadout()
{
    g_FieldReadout!.setText(Format.toString("Gui11.Field.Puck, % ms per trip", cast(s32, g_FieldDuration!.value())))
}

func layoutFieldPage()
{
    let page = g_FieldPage
    if not page do
        return

    let rect  = page.clientRect()
    let width = Math.max(rect.width - 2 * PagePad, 1.0)
    g_FieldNote!.setPosition(Math.Rectangle{PagePad, PagePad, width, NoteHeight})

    let controlsY = PagePad + NoteHeight + RowGap
    let controls  = unwrap g_FieldControls
    controls.setPosition(Math.Rectangle{PagePad, controlsY, width, PanelHeight})

    let inner = controls.contentRect()
    let rowY  = inner.y + CaptionGap
    g_FieldCaption!.setPosition(Math.Rectangle{inner.x, inner.y, inner.width, 20})

    var x = inner.x
    g_FieldEasing!.setPosition(Math.Rectangle{x, rowY, 168, BarHeight})
    x += 168 + 16
    g_FieldDuration!.setPosition(Math.Rectangle{x, rowY, 190, BarHeight})
    x += 190 + 16
    g_FieldPreserve!.setPosition(Math.Rectangle{x, rowY, 250, BarHeight})
    g_FieldClear!.setPosition(Math.Rectangle{inner.right() - 120, rowY, 120, BarHeight})
    g_FieldReadout!.setPosition(Math.Rectangle{inner.x, rowY + BarHeight + 8, inner.width, 22})

    let fieldY = controlsY + PanelHeight + RowGap
    g_Field!.setPosition(Math.Rectangle{PagePad, fieldY, width, Math.max(rect.height - fieldY - PagePad, 80.0)})
}

func onFieldPageEvent(_: *Wnd, evt: IEvent)->bool
{
    if evt is ResizeEvent do
        layoutFieldPage()
    return false
}

//////////////////////////////////////////////
// Preference page
//////////////////////////////////////////////

// Breathes the scale of one button forever, as decoration.
//
// The pivot stays at the center so the button grows out of its own middle, and the logical
// rectangle never changes, so the pointer target is exactly where it was before the loop started.
func startDecorativePulse()
{
    let btn = unwrap g_DecorativeBtn
    btn.setPresentationPivot({0.5, 0.5})

    with var options: AnimationOptions
    {
        .duration    = 900'ms
        .easing      = .EaseInOut
        .repeatCount = 0
        .autoReverse = true
        .motion      = .Decorative
    }

    discard app.animator.animateF32(btn,
                                    AnimationChannel.from("Gui11.Pref.Pulse"),
                                    1,
                                    1.06,
                                    &setCardScale,
                                    options)
}

// Breathes the opacity of one label forever, as feedback on work in progress.
func startEssentialBreath()
{
    with var options: AnimationOptions
    {
        .duration    = 1100'ms
        .easing      = .EaseInOut
        .repeatCount = 0
        .autoReverse = true
        .motion      = .Essential
    }

    discard app.animator.animateF32(unwrap g_EssentialLbl,
                                    AnimationChannel.from("Gui11.Pref.Breath"),
                                    1,
                                    0.35,
                                    &setCardOpacity,
                                    options)
}

func toggleExpander(_: *Button)
{
    g_Expanded        = not g_Expanded
    g_ExpandBtn!.name = g_Expanded ? "Hide the panel" : "Show the panel"
    g_ExpandBtn!.invalidate()
    discard app.animator.animateLayoutHeight(unwrap g_Detail, g_Expanded ? ExpandedDetail : CollapsedDetail)
}

func buildPrefPage(parent: *Wnd)->*Wnd
{
    let page = Wnd.create'Wnd(parent)
    page.backgroundStyle = .Transparent
    g_PrefPage = page

    g_PrefNote = Label.create(page, "A track says whether it decorates or whether it reports. Turn reduced motion on in the header: the left loop ends on its resting frame and the right one keeps going, because only one of them is carrying information.", {}, null, .WordWrap | .SecondaryText)

    let decorative = PanelWnd.create(page, "Decorative")
    g_Decorative     = decorative
    g_DecorativeBtn  = PushButton.create(decorative, "Ship it", {}, null, .Strong)
    g_DecorativeNote = Label.create(decorative, "An endless ping-pong on presentation scale. It exists to draw the eye, so a reader who asked for stillness gets the button at rest.", {}, null, .WordWrap | .SecondaryText)

    let essential = PanelWnd.create(page, "Essential")
    g_Essential     = essential
    g_EssentialLbl  = Label.create(essential, "Uploading three files...")
    g_EssentialNote = Label.create(essential, "The same endless ping-pong, on opacity, classified as essential. It answers a question the reader is asking, so the preference leaves it alone.", {}, null, .WordWrap | .SecondaryText)

    let expander = PanelWnd.create(page, "Layout")
    g_Expander = expander

    let btn = PushButton.create(expander, "Show the panel")
    g_ExpandBtn    = btn
    btn.sigPressed += &toggleExpander

    // The animated panel is the only docked child of its host, so growing it re-arranges exactly
    // one parent per frame: a `.Layout` track pays for a real measure and arrange, and this page
    // keeps that cost down to the block that is actually moving.
    let host = Wnd.create'Wnd(expander)
    g_ExpandHost         = host
    host.backgroundStyle = .Transparent

    let detail = Wnd.create'Wnd(host)
    g_Detail               = detail
    detail.backgroundStyle = .Panel
    detail.dockStyle       = .Top
    detail.preferredSize.y = CollapsedDetail
    detail.position.height = CollapsedDetail

    g_DetailText = Label.create(detail, "This panel changes the layout, not only the picture: the track carries an .Layout impact, so the parent is arranged again on every frame. That is why layout animation is a separate call from the presentation ones.", {12, 12, 400, 96}, null, .WordWrap | .SecondaryText)

    page.hookOnEvent = &onPrefPageEvent
    return page
}

func layoutPrefPage()
{
    let page = g_PrefPage
    if not page do
        return

    let rect  = page.clientRect()
    let width = Math.max(rect.width - 2 * PagePad, 1.0)
    g_PrefNote!.setPosition(Math.Rectangle{PagePad, PagePad, width, NoteHeight})

    let topY  = PagePad + NoteHeight + RowGap
    let topH  = 190.0
    let halfW = (width - RowGap) * 0.5
    g_Decorative!.setPosition(Math.Rectangle{PagePad, topY, halfW, topH})
    g_Essential!.setPosition(Math.Rectangle{PagePad + halfW + RowGap, topY, halfW, topH})

    let decoInner = g_Decorative!.contentRect()
    g_DecorativeBtn!.setPosition(Math.Rectangle{decoInner.x, decoInner.y, 150, 40})
    g_DecorativeNote!.setPosition(Math.Rectangle{decoInner.x, decoInner.y + 52, decoInner.width, decoInner.height - 52})

    let essInner = g_Essential!.contentRect()
    g_EssentialLbl!.setPosition(Math.Rectangle{essInner.x, essInner.y + 8, essInner.width, 24})
    g_EssentialNote!.setPosition(Math.Rectangle{essInner.x, essInner.y + 52, essInner.width, essInner.height - 52})

    let expY = topY + topH + RowGap
    let expH = Math.min(Math.max(rect.height - expY - PagePad, 120.0), 96 + ExpandedDetail)
    g_Expander!.setPosition(Math.Rectangle{PagePad, expY, width, expH})

    let expInner = g_Expander!.contentRect()
    g_ExpandBtn!.setPosition(Math.Rectangle{expInner.x, expInner.y, 170, 36})
    let hostHeight = Math.max(expInner.height - 46, 20.0)
    g_ExpandHost!.setPosition(Math.Rectangle{expInner.x, expInner.y + 46, expInner.width, hostHeight})
    g_DetailText!.setPosition(Math.Rectangle{12, 12, Math.max(expInner.width - 24, 40.0), ExpandedDetail - 24})
}

func onPrefPageEvent(_: *Wnd, evt: IEvent)->bool
{
    if evt is ResizeEvent do
        layoutPrefPage()
    return false
}

//////////////////////////////////////////////
// Surface
//////////////////////////////////////////////

// Places the header under the window strip, then the pages, keeping the foot clear for the hint
// line. The reduced-motion switch stands at the right of the tabs: it is what every page answers.
func layoutRootView()
{
    let view = g_View
    if not view do
        return

    let metrics = view.themeMetrics()
    let rect    = view.clientRect()
    let top     = view.stripInset()
    let width   = Math.max(rect.width - 2 * PageMargin, 1.0)

    let titleHeight = view.theme().createDefaultFont(TitleSize, .Bold).height
    g_Title!.setPosition(Math.Rectangle{PageMargin, top, width, titleHeight})
    g_SubTitle!.setPosition(Math.Rectangle{PageMargin, top + titleHeight + 4, width, 22})

    let tabsY  = top + titleHeight + 4 + 22 + 16
    let bottom = rect.height - metrics.hintLine_Bottom - metrics.hintLine_Height - 16
    g_Tabs!.setPosition(Math.Rectangle{PageMargin, tabsY, width, Math.max(bottom - tabsY, 120.0)})
    g_Reduced!.setPosition(Math.Rectangle{PageMargin + width - ReducedWidth, tabsY + (metrics.tabBar_FlatHeight - BarHeight) * 0.5 - 4, ReducedWidth, BarHeight})
}

// Answers the lens with the pages, the one shown checked, and the motion preference.
func describeChoices(results: *Lens.Results)
{
    const PagesFamily = "Pages"
    let tabs = unwrap g_Tabs
    var section: *Lens.Section?
    for name, index in PageNames
    {
        if not Lens.match(results.query, PagesFamily).matched and not Lens.match(results.query, name).matched do
            continue
        if not section do
            section = results.addSection(PagesFamily)
        with let entry = section.addEntry(name)
        {
            .checked = cast(u32, index) == tabs.selectedIndex
            .run     = func|index|() { g_Tabs!.setSelectedIndex(cast(u32, index)) }
        }
    }

    const MotionFamily = "Motion"
    const Reduced      = "Reduced Motion"
    if Lens.match(results.query, MotionFamily).matched or Lens.match(results.query, Reduced).matched
    {
        with let entry = results.addSection(MotionFamily).addEntry(Reduced)
        {
            .checked = app.isReducedMotion()
            .run     = func() { toggleReduced() }
        }
    }
}

const CmdLens   = "gui11.lens"
const PageNames = ["Curves", "Choreography", "Interruption", "Preference"]

func onRootEvent(_: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case ResizeEvent:
        layoutRootView()

    case CommandEvent as cmd where cmd.id == CmdLens:
        g_Lens!.open()
        cmd.accepted = true
        return true

    case DestroyEvent:
        app.sigFrame.disable()
        g_Surface, g_View, g_Title, g_SubTitle, g_Hint, g_Lens, g_Appearance, g_Reduced, g_Tabs = null
        g_CurvePage, g_CurveNote, g_Wall = null
        g_StagePage, g_StageNote, g_StageControls, g_StageEasing, g_StageDuration, g_StageStagger, g_StageReadout, g_StageReplay, g_StageHint = null
        g_FieldPage, g_FieldNote, g_FieldControls, g_FieldEasing, g_FieldDuration, g_FieldReadout, g_FieldPreserve, g_FieldClear, g_FieldCaption, g_Field = null
        g_PrefPage, g_PrefNote, g_Decorative, g_DecorativeBtn, g_DecorativeNote, g_Essential, g_EssentialLbl, g_EssentialNote = null
        g_Expander, g_ExpandBtn, g_ExpandHost, g_Detail, g_DetailText = null
        g_Cards.clear()
        g_StageCaptions.clear()
    }

    return false
}

// Drives the smoke run through every page and replays what each of them demonstrates.
func onFrame(_: *Application)
{
    if not Env.isSmokeRun() or not g_Tabs do
        return

    g_SmokeFrame += 1
    if g_SmokeFrame % SmokeFramesPerPage do
        return

    // Every page in Encre, then every page in Papier, with the lens opened once on the way.
    let next = (g_Tabs!.selectedIndex + 1) % 4
    if next == 0
    {
        if g_Light
        {
            Env.exit(0)
            return
        }

        g_Light = true
        g_Appearance!.setAppearanceTheme(.Light)
    }

    if next == 1 do
        g_Lens!.open("re")
    else do
        g_Lens!.close()
    g_Tabs!.setSelectedIndex(next)
    switch next
    {
    case 1:
        playEntrance()

    case 2:
        let rect = g_Field!.clientRect()
        g_Field!.moveTo(Math.Point{rect.x + rect.width * 0.25, rect.y + rect.height * 0.7})

    case 3:
        toggleExpander(unwrap g_ExpandBtn)
    }
}

func createRootView()
{
    let view = g_Surface!.view()
    g_View = view
    view.backgroundStyle = .Window

    with g_Title = Label.create(view, "Motion", {})
    {
        .setTextAlignment(.Left, .Center)
        .style.setFont(view.theme().createDefaultFont(TitleSize, .Bold), .Regular)
    }

    with g_SubTitle = Label.create(view, "Curves, choreography, interruption, and the preference that ends all three.", {}, null, .SecondaryText | .Ellipsis)
    {
        .setTextAlignment(.Left, .Center)
    }

    let tabs = Tab.create(view)
    g_Tabs = tabs
    tabs.setForms(.Flat, .Flat, .None)
    tabs.setPageTransitions(true)
    tabs.addItem(PageNames[0], view: buildCurvePage(tabs))
    tabs.addItem(PageNames[1], view: buildStagePage(tabs))
    tabs.addItem(PageNames[2], view: buildFieldPage(tabs))
    tabs.addItem(PageNames[3], view: buildPrefPage(tabs))

    // Created after the tabs, so it stands over their bar.
    with g_Reduced = CheckButton.create(view, "Reduced motion")
    {
        .sigChanged += &onReducedChanged
    }

    g_Hint = HintLine.create(view)

    // The appearance is a lens entry like every other command; the button only owns the choice.
    with g_Appearance = AppearanceButton.create(unwrap g_Surface)
    {
        .hide()
        .setAppearanceTheme(g_Light ? .Light : .Dark)
    }

    with g_Lens = Lens.View.create(view)
    {
        .addSource(.None, &describeChoices)
    }

    g_Appearance!.addToLens(unwrap g_Lens)

    view.registerKeyShortcut(.Control, .K, CmdLens)
    view.hookOnEvent = &onRootEvent
    layoutRootView()
}

#main
{
    let surface = try app.createSurface(90, 60, W, H, SurfaceFlags.StandardWindow)
    g_Surface = surface
    surface.setTitle("GUI11 Motion")
    surface.minSize = {1000, 720}

    for arg in Env.arguments() where arg == "--light" do
        g_Light = true
    createRootView()
    updateHint()

    app.sigFrame += &onFrame
    if Env.isSmokeRun() do
        app.maxRunFrame = 8 * SmokeFramesPerPage + 20

    surface.show()
    g_View!.applyLayout()
    restartLoops()
    playEntrance()
    app.run()
}
