#global internal

using Core, Gui, Pixel

// What the viewer is currently reporting.
//
// The report is named rather than written, so a language switch can say the same thing again
// without the viewer having kept a copy of the sentence.
enum StatusMessage
{
    Ready        // Nothing has been compiled yet.
    Working      // The compiler is running.
    Done         // The compiler printed the inspected function.
    NoOutput     // The compilation succeeded and printed nothing for this stage.
    Stopped      // The compiler reported an error, which the listing is showing.
}

// How a panel lays its viewer out.
enum PanelLayout
{
    Column      // Under the column header, beside the source.
    Stages      // Alone, stage by stage: the frieze, the readings of the chosen step and its listing.
    Compare     // Beside another build, with the innermost loop marked.
}

/*
One compilation running outside the interface thread.

The compiler is a separate process and a compilation is tens to hundreds of milliseconds, which is
long enough to stop a window that waits for it. The window submits the work instead and is told
when it ends, so it keeps drawing, keeps taking text, and keeps answering the reader while the
compiler runs.

Only one compilation per viewer runs at a time. A request that arrives while one is running
replaces whatever was waiting rather than joining a queue: the reader wants the answer to what they
last asked, not every version they passed through on the way to it.
*/
struct CompileJob
{
    task: Swag.Task     // Runs `MicrocodeViewer.runCompile` off the interface thread.

    // Inputs, copied before the task starts so the editor stays editable while it runs.
    request:    Pipeline.BuildRequest
    reused:     bool
    artifactId: u64

    // What the task left behind. The interface thread reads these only once the task is done.
    result:  Pipeline.Result
    elapsed: u64     // Milliseconds the compilation took, reported on the window's reading.

    running: bool     // Whether a task is in flight, which is what makes a new request wait.
    queued:  bool     // Whether a request arrived while one was, and runs as soon as it ends.
}

/*
The instructions the compiler makes of the first function of the source.

One compilation prints the function at every offered stage, so choosing a stage or stepping through
them never compiles again. In a column the viewer lists the chosen stage. Stage by stage, a frieze
names the steps that changed the code, the margin reads what the chosen one did, and its listing
strikes out what it removed and marks what it added. Beside another build, the viewer lists the
chosen stage with its innermost loop marked.
*/
struct MicrocodeViewer
{
    using wnd: Wnd

    late
    {
        panel:        *ViewerPanel
        cache:        *Pipeline.CompilationCache
        sourceEditor: *RichEditCtrl
        listing:      *ListingView
        frieze:       *StageFrieze
        since:        *SectionLabel
        showChange:   *ToggleButton
        changeLabel:  *Label
    }

    sigChanged:     SigArray'func||(*Wnd)
    job:            CompileJob
    pendingRequest: Pipeline.BuildRequest
    statusMessage:  StatusMessage
    inspection:     Pipeline.Inspection
    compiled:       bool     // Whether a compilation has ended and left a result.
    stage:          u32 = Pipeline.DefaultStage     // The stage the column lists.
    step:           u64      // The step chosen stage by stage.
    layout:         PanelLayout
}

impl MicrocodeViewer
{
    const MarginWidth  = 220.0      // The readings of the chosen step, beside its listing.
    const ReadingWidth = 640.0      // Widest the listing gets stage by stage.
    const FriezeGap    = 32.0       // Air between the frieze and what it chose.
    const FigureSize   = 30'u32     // Size of the count a step changed.

    // Builds the listing, the frieze and the readings of a step, which show stage by stage only.
    func create(parent: *ViewerPanel, sourceEditor: *RichEditCtrl)->*MicrocodeViewer
    {
        with let result = Wnd.create'MicrocodeViewer(parent, "prism.microcode")
        {
            .backgroundStyle = .Transparent
            .panel           = parent
            .cache           = parent.cache
            .sourceEditor    = sourceEditor
        }

        result.listing = ListingView.create(result, "prism.listing")
        with result.frieze = StageFrieze.create(result, "prism.frieze")
        {
            .sigChosen += func|viewer = result|(index) { viewer.setStep(index) }
        }

        result.since = SectionLabel.create(result, "")
        with result.showChange = ToggleButton.create(result)
        {
            .setChecked(true)
            .sigChanged += func|viewer = result|(_) { viewer.refreshListing() }
        }

        with result.changeLabel = Label.create(result, "", {}, null, .SecondaryText)
        {
            .setTextAlignment(.Left, .Center)
        }

        result.retranslate()
        result.setLayout(.Column)
        return result
    }

    // Lays the viewer out for `layout`: only stage by stage shows the frieze and the readings.
    mtd setLayout(layout: PanelLayout)
    {
        .layout = layout
        let stages = layout == .Stages
        .frieze.show(stages)
        .since.show(stages)
        .showChange.show(stages)
        .changeLabel.show(stages)
        .listing.setMarkLoop(layout == .Compare)
        .refreshListing()
        .arrangeParts()
    }

    // Lists the stage `stage` in a column; stage by stage, chooses the step in force at that stage.
    mtd setStage(stage: u32)
    {
        .stage = stage
        let printing = .inspection.lastOf(stage)
        if printing != Swag.U64.Max do
            .step = .inspection.stepAt(printing)
        .refreshListing()
        .sigChanged.call(me)
    }

    // Chooses the step `index` of the frieze.
    mtd setStep(index: u64)
    {
        if .inspection.steps.isEmpty() do
            return
        .step = Math.min(index, .inspection.steps.count - 1)
        let stage = .inspection.snapshots[.inspection.steps[.step]].stage
        if stage != Swag.U32.Max do
            .stage = stage
        .refreshListing()
        .sigChanged.call(me)
    }

    // Moves the chosen step by `delta`, staying on the first or the last one.
    mtd stepBy(delta: s64)
    {
        if .inspection.steps.isEmpty() do
            return
        let target = Math.clamp(cast(s64, .step) + delta, 0, cast(s64, .inspection.steps.count) - 1)
        .setStep(cast(u64, target))
    }

    // Returns the printing on screen, or null when the listing shows words instead.
    mtd shown()->const *Pipeline.Snapshot?
    {
        if not .compiled or .job.result.failed do
            return null
        if .layout == .Stages
        {
            if .inspection.steps.isEmpty() do
                return null
            return &.inspection.snapshots[.inspection.steps[.step]]
        }

        let printing = .inspection.lastOf(.stage)
        if printing == Swag.U64.Max do
            return null
        return &.inspection.snapshots[printing]
    }

    // Returns the printing before the chosen step, which the step is compared with.
    mtd previous()->const *Pipeline.Snapshot?
    {
        if .layout != .Stages or not .compiled or .inspection.steps.isEmpty() do
            return null
        let printing = .inspection.steps[.step]
        if printing == 0 do
            return null
        return &.inspection.snapshots[printing - 1]
    }

    // Shows the chosen stage or step, the compiler's words when it stopped, or the hint.
    mtd refreshListing()
    {
        let shown = .shown()
        if not .compiled
        {
            .listing.showHint(appStrings().ui_OutputHint)
        }
        elif .job.result.failed
        {
            .listing.showOutput(.job.result.text)
        }
        elif shown
        {
            .listing.setShowMarks(.showChange.isChecked())
            .listing.showListing(.previous(), shown)
        }
        else
        {
            .listing.showHint(appStrings().ui_NoOutput)
        }

        if .compiled and not .job.result.failed and .statusMessage != .Working do
            .statusMessage = shown ? StatusMessage.Done : StatusMessage.NoOutput
        .refreshFrieze()
        .invalidate()
    }

    // Names the steps of the frieze and what the chosen one did.
    mtd refreshFrieze()
    {
        let count = .inspection.steps.count
        if not .compiled or .job.result.failed or count == 0
        {
            .frieze.set(0, 0, "", "", "", "")
            return
        }

        .frieze.set(count, .step, .stepName(0), .stepName(count - 1), .stepName(.step), .changeText())
    }

    // Returns the name of the stage the step `step` printed.
    mtd stepName(step: u64)->string
    {
        let stage = .inspection.snapshots[.inspection.steps[step]].stage
        if stage >= Pipeline.Stages.count do
            return ""
        return Pipeline.stageLabels()[stage]
    }

    // Returns what the chosen step did to the count, signed, with its unit: "−2 instructions".
    mtd changeText()->String
    {
        let shown    = .shown()
        let previous = .previous()
        if not shown or not previous do
            return {}
        return countText(cast(s64, shown.instructions) - cast(s64, previous.instructions), withSign: true)
    }

    // Asks for `request` to be compiled.
    //
    // One compilation is in flight at a time. Asking again while one runs marks the request rather
    // than starting a second compiler, and the marked request runs as soon as the first ends — so
    // a burst of edits costs one more compilation, not one per keystroke.
    mtd compileRequest(request: Pipeline.BuildRequest)
    {
        .pendingRequest = request
        if .job.running
        {
            .job.queued = true
            .job.task.cancel()
            return
        }

        .startCompile()
    }

    // Copies what is to be compiled and submits it, leaving the window free to draw and take text.
    mtd startCompile()
    {
        .job.request = .pendingRequest
        .job.queued  = false
        .job.running = true
        .setStatus(.Working)
        .job.task.submit(func|viewer = me|() { viewer.runCompile() }, .taskNotifier(&.job.task))
    }

    // Runs on the job's thread. Nothing here may reach the window tree or anything it draws from.
    mtd runCompile()
    {
        var lease = .cache.acquire(.job.request)
        if not lease.wait() do
            return
        .job.result     = lease.artifact!.result
        .job.elapsed    = lease.artifact.elapsedMs
        .job.artifactId = lease.artifact.id
        .job.reused     = lease.reused
    }

    // Reads what the finished job produced, then starts whatever was asked for meanwhile.
    mtd finishCompile()
    {
        .job.running = false
        if .job.queued
        {
            .startCompile()
            return
        }

        .showResult()
    }

    // Reads the compiler's output of the job as the listing, keeping the chosen stage.
    mtd showResult()
    {
        .compiled   = true
        .inspection = Pipeline.Inspection.parse(.job.result.text)
        let printing = .inspection.lastOf(.stage)
        .step = printing == Swag.U64.Max ? 0 : .inspection.stepAt(printing)
        .statusMessage = .Ready
        .refreshListing()
        if .job.result.failed do
            .statusMessage = .Stopped
        .setStatus(.statusMessage)
    }

    // Waits for a compilation still in flight, so the probe it reads is not destroyed under it.
    mtd stopCompile()
    {
        if .job.running
        {
            .job.task.cancel()
            .job.task.wait()
        }

        .job.running = false
        .job.queued  = false
    }

    mtd setStatus(message: StatusMessage)
    {
        .statusMessage = message
        .sigChanged.call(me)
    }

    // Returns the outcome of the latest compilation, in the active language.
    mtd statusReading()->String
    {
        let strings = appStrings()
        switch #complete .statusMessage
        {
        case .Ready:    return {}
        case .Working:  return strings.ui_Working
        case .NoOutput: return strings.ui_NoOutput
        case .Stopped:  return strings.ui_Stopped

        // An application about what the compiler does says how long it took to do it: the number
        // is the reader's own measurement of the tool they came here to judge.
        case .Done: return Format.toString(.job.reused ? strings.ui_ReusedBuild : strings.ui_Done, .job.elapsed)
        }
    }

    // Writes the readings of the step and the hint in the active language.
    mtd retranslate()
    {
        .since.setText(appStrings().ui_SincePrevious)
        .changeLabel.setText(appStrings().cmd_ShowChange)
        .refreshListing()
        .arrangeParts()
    }

    // Places the listing alone, or stage by stage under the frieze and beside the readings.
    mtd arrangeParts()
    {
        // The viewer lays itself out while its parts are still being created.
        if .changeLabel == null do
            return

        let client = .clientRect()
        if .layout != .Stages
        {
            .listing.scroll.setPosition(client)
            return
        }

        let top = StageFrieze.Height + FriezeGap
        .frieze.setPosition(Math.Rectangle{0, 0, client.width, StageFrieze.Height})
        .since.setPosition(Math.Rectangle{0, top, MarginWidth - 24, 20})

        let toggleTop = top + 112
        .showChange.setPosition(Math.Rectangle{0, toggleTop, 34, 20})
        .changeLabel.setPosition(Math.Rectangle{44, toggleTop - 4, MarginWidth - 44, 28})

        let listingWidth = Math.min(ReadingWidth, Math.max(0'f32, client.width - MarginWidth))
        .listing.scroll.setPosition(Math.Rectangle{MarginWidth, top - ListingView.Padding, listingWidth, Math.max(0'f32, client.height - top)})
    }
}

// Writes a count of instructions with its unit, signed with a true minus when `withSign` asks.
func countText(count: s64, withSign = false)->String
{
    var result: #returntype
    if withSign do
        result.append(signOf(count))
    let size = Math.abs(count)
    result.appendFormat("% %", size, size == 1 ? appStrings().ui_InstructionOne : appStrings().ui_InstructionMany)
    return result
}

// Returns the sign a change of `count` is written with: a true minus, a plus, or `±` for none.
func signOf(count: s64)->string
{
    if count < 0 do
        return "−"
    if count > 0 do
        return "+"
    return "±"
}

impl IViewer for MicrocodeViewer
{
    mtd impl window()->*Wnd => &.wnd
    mtd impl compile(request: Pipeline.BuildRequest) { .compileRequest(request) }
    mtd impl inspects()->bool => true
    mtd impl isPaused()->bool => false
    mtd impl setPaused(_: bool) {}
    mtd impl shutdown() { .stopCompile() }
    mtd impl isRunning()->bool => .job.running
    mtd impl reading()->String => .statusReading()
    mtd impl subscribeChanged(action: func||(*Wnd)) { .sigChanged += action }
}

impl IWnd for MicrocodeViewer
{
    // Stage by stage, the margin reads what the chosen step did: the change of the count, large,
    // and how many instructions it removed and added.
    mtd impl onPaint(evt: *PaintEvent)
    {
        let shown    = .shown()
        let previous = .previous()
        if .layout != .Stages or not shown or not previous do
            return

        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let delta   = cast(s64, shown.instructions) - cast(s64, previous.instructions)
        let size    = Math.abs(delta)
        var figure: String
        if delta do
            figure.append(signOf(delta))
        figure.appendFormat("%", size)

        let top        = StageFrieze.Height + FriezeGap
        let figureFont = .theme().createDefaultFont(FigureSize)
        let wordsFont  = .theme().createDefaultFont(.themeMetrics().defaultFontSize)
        let figureY    = top + 44
        let unit       = size == 1 ? appStrings().ui_InstructionOne : appStrings().ui_InstructionMany
        painter.drawString(0, figureFont.opticalLineTop(figureY), figure, figureFont, colors.text)
        let figureWidth = Painter.measureString(figure, figureFont).width
        painter.drawString(figureWidth + 6, wordsFont.opticalLineTop(figureY + 4), unit, wordsFont, colors.softText)

        // How many lines the step removed, in the soft ink, and how many it added, in the Arc of
        // their mark.
        let countsY = top + 80
        let removed = Format.toString(appStrings().ui_Removed, .listing.difference.removed)
        let added   = Format.toString(appStrings().ui_Added, .listing.difference.added)
        let between = " · "
        var x       = 0'f32
        painter.drawString(x, wordsFont.opticalLineTop(countsY), removed, wordsFont, colors.softText)
        x += Painter.measureString(removed, wordsFont).width
        painter.drawString(x, wordsFont.opticalLineTop(countsY), between, wordsFont, colors.faintText)
        x += Painter.measureString(between, wordsFont).width
        painter.drawString(x, wordsFont.opticalLineTop(countsY), added, wordsFont, colors.arc)
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .arrangeParts()
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if evt.task == &.job.task and .job.running and .job.task.isDone() do
            .finishCompile()
        else do
            evt.accepted = false
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .stopCompile()
        .wnd.IWnd.onDestroyEvent(evt)
    }
}
