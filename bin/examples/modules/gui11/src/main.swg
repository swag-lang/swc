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

const RootMargin  = 24.0
const HeaderTop   = 16.0
const BarHeight   = 34.0
const BarY        = 96.0
const TabsY       = 142.0
const FooterSpace = 42.0
const PagePad     = 18.0
const NoteHeight  = 38.0
const RowGap      = 12.0
const PanelHeight = 146.0
const CaptionGap  = 22.0
const MaxCardH    = 176.0

const SmokeFramesPerPage = 40

var app: Application

var g_Surface:     #null *Surface
var g_View:        #null *Wnd
var g_Title:       #null *Label
var g_SubTitle:    #null *Label
var g_Footer:      #null *Label
var g_ThemeButton: #null *PushButton
var g_Reduced:     #null *CheckButton
var g_Tabs:        #null *Tab

var g_DarkTheme = true
var g_SmokeFrame: u32

// Curves page.
var g_CurvePage: #null *Wnd
var g_CurveNote: #null *Label
var g_Wall:      #null *CurveWall

// Choreography page.
var g_StagePage:     #null *Wnd
var g_StageNote:     #null *Label
var g_StageControls: #null *PanelWnd
var g_StageEasing:   #null *ComboBox
var g_StageDuration: #null *Slider
var g_StageStagger:  #null *Slider
var g_StageReadout:  #null *Label
var g_StageReplay:   #null *PushButton
var g_StageHint:     #null *Label
var g_StageCaptions: Array'(*Label)
var g_Cards:         Array'(*MotionCard)

// Interruption page.
var g_FieldPage:     #null *Wnd
var g_FieldNote:     #null *Label
var g_FieldControls: #null *PanelWnd
var g_FieldEasing:   #null *ComboBox
var g_FieldDuration: #null *Slider
var g_FieldReadout:  #null *Label
var g_FieldPreserve: #null *CheckButton
var g_FieldClear:    #null *PushButton
var g_FieldCaption:  #null *Label
var g_Field:         #null *MotionField

// Preference page.
var g_PrefPage:       #null *Wnd
var g_PrefNote:       #null *Label
var g_Decorative:     #null *PanelWnd
var g_DecorativeBtn:  #null *PushButton
var g_DecorativeNote: #null *Label
var g_Essential:      #null *PanelWnd
var g_EssentialLbl:   #null *Label
var g_EssentialNote:  #null *Label
var g_Expander:       #null *PanelWnd
var g_ExpandBtn:      #null *PushButton
var g_ExpandHost:     #null *Wnd
var g_Detail:         #null *Wnd
var g_DetailText:     #null *Label
var g_Expanded:       bool

const StageCardCount = 6

const StageTitles = ["Group", "Stagger", "Curve", "Scale", "Fade", "Rise"]

const StageDetails = ["one start", "per index", "one shape", "0.86 to 1", "0 to 1", "42 to 0"]

const CollapsedDetail = 1.0
const ExpandedDetail  = 132.0

//////////////////////////////////////////////
// Theme and motion preference
//////////////////////////////////////////////

func applyTheme()
{
    if g_DarkTheme do
        app.theme.setDark()
    else do
        app.theme.setLight()

    let btn = g_ThemeButton
    if btn
    {
        btn.name = g_DarkTheme ? "Light theme" : "Dark theme"
        btn.invalidate()
    }

    app.notifyThemeChanged()
}

func toggleTheme(btn: *Button)
{
    discard btn
    g_DarkTheme = !g_DarkTheme
    applyTheme()
}

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
    updateFooter()
}

func updateFooter()
{
    let reduced = app.isReducedMotion()
    g_Footer!.setText(reduced
                      ? "Reduced motion is on: decorative tracks end on their resting frame, essential ones keep reporting."
                      : "Reduced motion is off: every track runs on the application frame clock.")
}

//////////////////////////////////////////////
// Curves page
//////////////////////////////////////////////

func buildCurvePage(parent: *Wnd)->*Wnd
{
    let page = Wnd.create'Wnd(parent)
    page.backgroundStyle = .View
    g_CurvePage          = page

    g_CurveNote = Label.create(page, "Nine curves, one clock. The dot on the graph and the puck under it are the same number: the shape is the movement. The clock repeats forever and reverses on every play, which is one track, not a frame callback.", {}, null, .WordWrap | .SecondaryText)
    g_Wall      = CurveWall.create(page)

    page.hookOnEvent = &onCurvePageEvent
    return page
}

func layoutCurvePage()
{
    let page = g_CurvePage
    if !page do
        return

    let rect  = page.clientRect()
    let width = Math.max(rect.width - 2 * PagePad, 1.0)
    g_CurveNote!.setPosition({PagePad, PagePad, width, NoteHeight})
    g_Wall!.setPosition({PagePad, PagePad + NoteHeight + RowGap, width, Math.max(rect.height - 2 * PagePad - NoteHeight - RowGap, 1.0)})
}

func onCurvePageEvent(page: *Wnd, evt: IEvent)->bool
{
    discard page
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
    wnd.setPresentationScale({value, value})
}

func buildStagePage(parent: *Wnd)->*Wnd
{
    let page = Wnd.create'Wnd(parent)
    page.backgroundStyle = .View
    g_StagePage          = page

    g_StageNote = Label.create(page, "Six tiles, one parallel group, eighteen tracks. Each tile fades, rises, and grows on the same timeline, offset by its rank. Nothing below moves: presentation state never touches a layout rectangle.", {}, null, .WordWrap | .SecondaryText)

    let controls = PanelWnd.create(page, "Timeline")
    g_StageControls = controls

    for caption in ["Curve", "Duration", "Stagger"] do
        g_StageCaptions.add(Label.create(controls, caption, {}, null, .SecondaryText))

    let easing = ComboBox.create(controls)
    g_StageEasing = easing
    for [index] in @countof(WallCurves) do
        discard easing.addItem(curveName(WallCurves[index]))
    easing.setSelectedIndex(5, false)
    easing.sigChanged += func(box, index)
    {
        discard box
        discard index
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
    replay.sigPressed += func(btn)
    {
        discard btn
        playEntrance()
    }

    for [index] in StageCardCount do
        g_Cards.add(MotionCard.create(page, cast(s32) index + 1, StageTitles[index], StageDetails[index]))

    g_StageHint = Label.create(page, "Press Replay while the strip is still arriving: each tile keeps the value it is showing and continues from there.", {}, null, .SecondaryText)

    updateStageReadout()
    page.hookOnEvent = &onStagePageEvent
    return page
}

func onStageSlider(slider: *Slider)
{
    discard slider
    updateStageReadout()
    playEntrance()
}

func updateStageReadout()
{
    let duration = g_StageDuration!.value()
    let stagger  = g_StageStagger!.value()
    let last     = duration + stagger * cast(f32) (StageCardCount - 1)
    g_StageReadout!.setText(Format.toString("% ms each, % ms apart, % ms until the last tile lands", cast(s32) duration, cast(s32) stagger, cast(s32) last))
}

// Replays the whole entrance from wherever the tiles currently are.
//
// Pressing Replay while the strip is still arriving is the interesting case: the group replaces
// the running one channel by channel, so every tile continues from the value on screen instead of
// snapping back to the start of the timeline.
func playEntrance()
{
    let curve    = WallCurves[g_StageEasing!.selectedIndex]
    let duration = Time.Duration.fromSeconds(cast(f64) g_StageDuration!.value() / 1000)
    let stagger  = cast(f64) g_StageStagger!.value() / 1000

    var group = AnimationGroup.parallel()
    for card, [index] in g_Cards
    {
        let wnd   = card!
        let delay = Time.Duration.fromSeconds(stagger * cast(f64) index)

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

func onEntranceEnded(result: AnimationResult)
{
    discard result

    // Presentation state is dropped once it is back at rest, so a settled tile costs the painter
    // nothing: no layer, no resample, no per-frame composition.
    for card in g_Cards
    {
        if !card!.isPendingDestroy do
            card!.resetPresentation()
    }
}

func layoutStagePage()
{
    let page = g_StagePage
    if !page do
        return

    let rect  = page.clientRect()
    let width = Math.max(rect.width - 2 * PagePad, 1.0)
    g_StageNote!.setPosition({PagePad, PagePad, width, NoteHeight})

    let controlsY = PagePad + NoteHeight + RowGap
    let controls  = g_StageControls!
    controls.setPosition({PagePad, controlsY, width, PanelHeight})

    let inner   = controls.contentRect()
    let rowY    = inner.y + CaptionGap
    let columns = [168.0, 190.0, 190.0]
    var x       = inner.x
    for caption, [index] in g_StageCaptions
    {
        caption!.setPosition({x, inner.y, columns[index], 20})
        x += columns[index] + 16
    }

    x = inner.x
    g_StageEasing!.setPosition({x, rowY, columns[0], BarHeight})
    x += columns[0] + 16
    g_StageDuration!.setPosition({x, rowY, columns[1], BarHeight})
    x += columns[1] + 16
    g_StageStagger!.setPosition({x, rowY, columns[2], BarHeight})
    g_StageReplay!.setPosition({inner.right() - 120, rowY, 120, BarHeight})
    g_StageReadout!.setPosition({inner.x, rowY + BarHeight + 8, inner.width, 22})

    let stripY = controlsY + PanelHeight + RowGap
    let cardH  = Math.clamp(rect.height - stripY - PagePad - 30, 90.0, MaxCardH)
    let cardW  = (width - cast(f32) (StageCardCount - 1) * RowGap) / cast(f32) StageCardCount

    for card, [index] in g_Cards do
        card!.setPosition({PagePad + cast(f32) index * (cardW + RowGap), stripY, cardW, cardH})
    g_StageHint!.setPosition({PagePad, stripY + cardH + 10, width, 22})
}

func onStagePageEvent(page: *Wnd, evt: IEvent)->bool
{
    discard page
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
    page.backgroundStyle = .View
    g_FieldPage          = page

    g_FieldNote = Label.create(page, "One channel owns the puck. Clicking again while it travels does not stack a second animation: it replaces the first one from the value on screen, which is why the trail bends instead of jumping.", {}, null, .WordWrap | .SecondaryText)

    let controls = PanelWnd.create(page, "Track")
    g_FieldControls = controls

    g_FieldCaption = Label.create(controls, "Curve, duration, and how a replacement treats the run it interrupts", {}, null, .SecondaryText)

    let easing = ComboBox.create(controls)
    g_FieldEasing = easing
    for [index] in @countof(WallCurves) do
        discard easing.addItem(curveName(WallCurves[index]))
    easing.setSelectedIndex(2, false)
    easing.sigChanged += func(box, index)
    {
        discard box
        g_Field!.easing = WallCurves[index]
    }

    let duration = Slider.create(controls)
    g_FieldDuration = duration
    duration.setBounds(200, 2000)
    duration.setValue(900)
    duration.sigChanged += func(slider)
    {
        g_Field!.travelTime = Time.Duration.fromSeconds(cast(f64) slider.value() / 1000)
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
    clear.sigPressed += func(btn)
    {
        discard btn
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
    g_FieldReadout!.setText(Format.toString("Gui11.Field.Puck, % ms per trip", cast(s32) g_FieldDuration!.value()))
}

func layoutFieldPage()
{
    let page = g_FieldPage
    if !page do
        return

    let rect  = page.clientRect()
    let width = Math.max(rect.width - 2 * PagePad, 1.0)
    g_FieldNote!.setPosition({PagePad, PagePad, width, NoteHeight})

    let controlsY = PagePad + NoteHeight + RowGap
    let controls  = g_FieldControls!
    controls.setPosition({PagePad, controlsY, width, PanelHeight})

    let inner = controls.contentRect()
    let rowY  = inner.y + CaptionGap
    g_FieldCaption!.setPosition({inner.x, inner.y, inner.width, 20})

    var x = inner.x
    g_FieldEasing!.setPosition({x, rowY, 168, BarHeight})
    x += 168 + 16
    g_FieldDuration!.setPosition({x, rowY, 190, BarHeight})
    x += 190 + 16
    g_FieldPreserve!.setPosition({x, rowY, 250, BarHeight})
    g_FieldClear!.setPosition({inner.right() - 120, rowY, 120, BarHeight})
    g_FieldReadout!.setPosition({inner.x, rowY + BarHeight + 8, inner.width, 22})

    let fieldY = controlsY + PanelHeight + RowGap
    g_Field!.setPosition({PagePad, fieldY, width, Math.max(rect.height - fieldY - PagePad, 80.0)})
}

func onFieldPageEvent(page: *Wnd, evt: IEvent)->bool
{
    discard page
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
    let btn = g_DecorativeBtn!
    btn.setPresentationPivot({0.5, 0.5})

    var options: AnimationOptions
    options.duration    = 900'ms
    options.easing      = .EaseInOut
    options.repeatCount = 0
    options.autoReverse = true
    options.motion      = .Decorative

    discard app.animator.animateF32(btn, AnimationChannel.from("Gui11.Pref.Pulse"), 1, 1.06, &setCardScale, options)
}

// Breathes the opacity of one label forever, as feedback on work in progress.
func startEssentialBreath()
{
    var options: AnimationOptions
    options.duration    = 1100'ms
    options.easing      = .EaseInOut
    options.repeatCount = 0
    options.autoReverse = true
    options.motion      = .Essential

    discard app.animator.animateF32(g_EssentialLbl!, AnimationChannel.from("Gui11.Pref.Breath"), 1, 0.35, &setCardOpacity, options)
}

func toggleExpander(btn: *Button)
{
    discard btn
    g_Expanded        = !g_Expanded
    g_ExpandBtn!.name = g_Expanded ? "Hide the panel" : "Show the panel"
    g_ExpandBtn!.invalidate()
    discard app.animator.animateLayoutHeight(g_Detail!, g_Expanded ? ExpandedDetail : CollapsedDetail)
}

func buildPrefPage(parent: *Wnd)->*Wnd
{
    let page = Wnd.create'Wnd(parent)
    page.backgroundStyle = .View
    g_PrefPage           = page

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
    detail.backgroundStyle = .Window
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
    if !page do
        return

    let rect  = page.clientRect()
    let width = Math.max(rect.width - 2 * PagePad, 1.0)
    g_PrefNote!.setPosition({PagePad, PagePad, width, NoteHeight})

    let topY  = PagePad + NoteHeight + RowGap
    let topH  = 190.0
    let halfW = (width - RowGap) * 0.5
    g_Decorative!.setPosition({PagePad, topY, halfW, topH})
    g_Essential!.setPosition({PagePad + halfW + RowGap, topY, halfW, topH})

    let decoInner = g_Decorative!.contentRect()
    g_DecorativeBtn!.setPosition({decoInner.x, decoInner.y, 150, 40})
    g_DecorativeNote!.setPosition({decoInner.x, decoInner.y + 52, decoInner.width, decoInner.height - 52})

    let essInner = g_Essential!.contentRect()
    g_EssentialLbl!.setPosition({essInner.x, essInner.y + 8, essInner.width, 24})
    g_EssentialNote!.setPosition({essInner.x, essInner.y + 52, essInner.width, essInner.height - 52})

    let expY = topY + topH + RowGap
    let expH = Math.min(Math.max(rect.height - expY - PagePad, 120.0), 96 + ExpandedDetail)
    g_Expander!.setPosition({PagePad, expY, width, expH})

    let expInner = g_Expander!.contentRect()
    g_ExpandBtn!.setPosition({expInner.x, expInner.y, 170, 36})
    g_ExpandHost!.setPosition({expInner.x, expInner.y + 46, expInner.width, Math.max(expInner.height - 46, 20.0)})
    g_DetailText!.setPosition({12, 12, Math.max(expInner.width - 24, 40.0), ExpandedDetail - 24})
}

func onPrefPageEvent(page: *Wnd, evt: IEvent)->bool
{
    discard page
    if evt is ResizeEvent do
        layoutPrefPage()
    return false
}

//////////////////////////////////////////////
// Surface
//////////////////////////////////////////////

func layoutRootView()
{
    let view = g_View
    if !view do
        return

    let rect  = view.clientRect()
    let width = Math.max(rect.width - 2 * RootMargin, 1.0)

    g_Title!.setPosition({RootMargin, HeaderTop, width, 36})
    g_SubTitle!.setPosition({RootMargin + 2, HeaderTop + 38, width - 4, 34})
    g_ThemeButton!.setPosition({RootMargin, BarY, 136, BarHeight})
    g_Reduced!.setPosition({RootMargin + 148, BarY, 190, BarHeight})

    let tabsH = Math.max(rect.height - TabsY - FooterSpace, 120.0)
    g_Tabs!.setPosition({RootMargin, TabsY, width, tabsH})
    g_Footer!.setPosition({RootMargin, TabsY + tabsH + 8, width, 24})
}

func onRootEvent(view: *Wnd, evt: IEvent)->bool
{
    discard view
    if evt is ResizeEvent
    {
        layoutRootView()
    }
    elif evt is DestroyEvent
    {
        app.sigFrame.disable()
        g_Surface        = null
        g_View           = null
        g_Title          = null
        g_SubTitle       = null
        g_Footer         = null
        g_ThemeButton    = null
        g_Reduced        = null
        g_Tabs           = null
        g_CurvePage      = null
        g_CurveNote      = null
        g_Wall           = null
        g_StagePage      = null
        g_StageNote      = null
        g_StageControls  = null
        g_StageEasing    = null
        g_StageDuration  = null
        g_StageStagger   = null
        g_StageReadout   = null
        g_StageReplay    = null
        g_StageHint      = null
        g_FieldPage      = null
        g_FieldNote      = null
        g_FieldControls  = null
        g_FieldEasing    = null
        g_FieldDuration  = null
        g_FieldReadout   = null
        g_FieldPreserve  = null
        g_FieldClear     = null
        g_FieldCaption   = null
        g_Field          = null
        g_PrefPage       = null
        g_PrefNote       = null
        g_Decorative     = null
        g_DecorativeBtn  = null
        g_DecorativeNote = null
        g_Essential      = null
        g_EssentialLbl   = null
        g_EssentialNote  = null
        g_Expander       = null
        g_ExpandBtn      = null
        g_ExpandHost     = null
        g_Detail         = null
        g_DetailText     = null
        g_Cards.clear()
        g_StageCaptions.clear()
    }

    return false
}

// Drives the smoke run through every page and replays what each of them demonstrates.
func onFrame(application: *Application)
{
    discard application
    if !Env.isSmokeRun() or !g_Tabs do
        return

    g_SmokeFrame += 1
    if g_SmokeFrame % SmokeFramesPerPage do
        return

    let next = (g_Tabs!.selectedIndex + 1) % 4
    g_Tabs!.setSelectedIndex(next)
    switch next
    {
    case 1:
        playEntrance()

    case 2:
        let rect = g_Field!.clientRect()
        g_Field!.moveTo({rect.x + rect.width * 0.25, rect.y + rect.height * 0.7})

    case 3:
        toggleExpander(g_ExpandBtn!)
    }
}

func createRootView()
{
    let view = g_Surface!.view()
    g_View               = view
    view.backgroundStyle = .View

    let title = Label.create(view, "GUI11 motion laboratory")
    g_Title = title
    title.style.setFont(view.theme().createDefaultFont(26), .Regular)
    title.setTextAlignment(.Left, .Center)

    let subTitle = Label.create(view, "Curves, choreography, interruption, and the preference that ends all three.", {}, null, .WordWrap | .SecondaryText)
    g_SubTitle = subTitle
    subTitle.setTextAlignment(.Left, .Top)

    let themeButton = PushButton.create(view, "", {}, null, .Flat)
    g_ThemeButton = themeButton
    themeButton.setIcon(app.theme.icon(ThemeIcons.Picker, 18))
    themeButton.sigPressed += &toggleTheme

    let reduced = CheckButton.create(view, "Reduced motion")
    g_Reduced          = reduced
    reduced.sigChanged += &onReducedChanged

    let tabs = Tab.create(view)
    g_Tabs = tabs
    tabs.setForm(.Button)
    tabs.setPageTransitions(true)
    discard tabs.addItem("Curves", view: buildCurvePage(tabs))
    discard tabs.addItem("Choreography", view: buildStagePage(tabs))
    discard tabs.addItem("Interruption", view: buildFieldPage(tabs))
    discard tabs.addItem("Preference", view: buildPrefPage(tabs))

    g_Footer = Label.create(view, "", {}, null, .SecondaryText)

    layoutRootView()
    view.hookOnEvent = &onRootEvent
}

#main
{
    let flags   = SurfaceFlags.LargeCaption | SurfaceFlags.MinimizeButton | SurfaceFlags.MaximizeButton | SurfaceFlags.CloseButton | SurfaceFlags.Border
    let surface = (try app.createSurface(90, 60, W - 46, H - 31, flags))!
    g_Surface = surface
    surface.setTitle("GUI11 motion laboratory")
    surface.setIcon(app.theme.icon(ThemeIcons.Play, 18))

    createRootView()
    applyTheme()
    updateFooter()

    app.sigFrame += &onFrame
    if Env.isSmokeRun() do
        app.maxRunFrame = 4 * SmokeFramesPerPage + 20

    surface.show()
    g_View!.applyLayout()
    restartLoops()
    playEntrance()
    app.run()
}
