using Gui

// The commands of the timeline of a timed capture: playback, frame stepping, and the time span of
// the selected forms.
struct ActionTimeline {}

impl ActionTimeline
{
    newCmdId("Play")
    newCmdId("PrevFrame")
    newCmdId("NextFrame")
    newCmdId("ShowFrom")
    newCmdId("ShowUntil")
    newCmdId("ShowAlways")
}

impl IActionUI for ActionTimeline
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main     = mainWndOf(cxt)
        let capture  = main.getCapture()
        let timed    = capture and capture.isTimed() and capture.frames and not main.libraryMode
        let selected = timed and capture!.selection.count

        evt.updatedFields |= .Name | .Icon | .Disabled
        switch cxt.id
        {
        case .Play:
            let playing = main.timeline and main.timeline.isPlaying()
            evt.name     = playing ? appStrings().act_PauseAnimation : appStrings().act_PlayAnimation
            evt.icon     = main.theme().icon(playing ? .Pause : .Play)
            evt.disabled = not timed

        case .PrevFrame:
            evt.name     = appStrings().act_PreviousFrame
            evt.icon     = main.theme().icon(.ChevronLeft)
            evt.disabled = not timed

        case .NextFrame:
            evt.name     = appStrings().act_NextFrame
            evt.icon     = main.theme().icon(.ChevronRight)
            evt.disabled = not timed

        case .ShowFrom:
            evt.name     = appStrings().act_ShowFromHere
            evt.icon     = main.theme().icon(.ChevronRight)
            evt.disabled = not selected

        case .ShowUntil:
            evt.name     = appStrings().act_ShowUntilHere
            evt.icon     = main.theme().icon(.ChevronLeft)
            evt.disabled = not selected

        case .ShowAlways:
            evt.name     = appStrings().act_ShowAlways
            evt.icon     = main.theme().icon(.Play)
            evt.disabled = not selected
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = mainWndOf(cxt)
        let capture = main.getCapture()
        if not capture or not capture.isTimed() do
            return true

        switch cxt.id
        {
        case .Play:
            main.timeline?.togglePlay()

        case .PrevFrame:
            catch capture.stepFrame(-1)
            main.timeline?.invalidate()

        case .NextFrame:
            catch capture.stepFrame(1)
            main.timeline?.invalidate()

        case .ShowFrom:
            capture.setSelectionSpan(start: true)
            main.timeline?.invalidate()

        case .ShowUntil:
            capture.setSelectionSpan(start: false)
            main.timeline?.invalidate()

        case .ShowAlways:
            capture.clearSelectionSpan()
            main.timeline?.invalidate()
        }

        return true
    }
}
