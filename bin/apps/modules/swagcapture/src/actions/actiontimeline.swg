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
    newCmdId("TrimStart")
    newCmdId("TrimEnd")
    newCmdId("KeepAll")
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
        let playhead = timed ? capture!.playheadTime() : 0
        var canShowFrom  = selected
        var canShowUntil = selected
        if selected
        {
            let selectedCapture = unwrap capture
            for index in selectedCapture.selection
            {
                let form: *BaseForm = selectedCapture.forms[index]
                let finish = form.timeEnd ? form.timeEnd : selectedCapture.timeline.duration
                canShowFrom  = canShowFrom and playhead < finish
                canShowUntil = canShowUntil and playhead > form.timeStart
            }
        }

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
            evt.icon     = main.theme().icon(.SearchPrevious)
            evt.disabled = not timed or capture!.playhead == 0

        case .NextFrame:
            evt.name     = appStrings().act_NextFrame
            evt.icon     = main.theme().icon(.SearchNext)
            evt.disabled = not timed or capture!.playhead >= capture.timeline.frameCount - 1

        case .ShowFrom:
            evt.name     = appStrings().act_ShowFromHere
            evt.icon     = main.theme().icon(.SeekForward)
            evt.disabled = not canShowFrom

        case .ShowUntil:
            evt.name     = appStrings().act_ShowUntilHere
            evt.icon     = main.theme().icon(.SeekBackward)
            evt.disabled = not canShowUntil

        case .ShowAlways:
            evt.name     = appStrings().act_ShowAlways
            evt.icon     = main.theme().icon(.Eye)
            evt.disabled = not selected

        case .TrimStart:
            evt.name     = appStrings().act_TrimStart
            evt.icon     = main.icon(.TimelineStart)
            evt.disabled = not timed or playhead >= capture!.trimEnd()

        case .TrimEnd:
            evt.name     = appStrings().act_TrimEnd
            evt.icon     = main.icon(.TimelineEnd)
            evt.disabled = not timed or playhead <= capture!.trimStart()

        case .KeepAll:
            evt.name     = appStrings().act_KeepAll
            evt.icon     = main.theme().icon(.History)
            evt.disabled = not timed or not capture!.isTrimmed()
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

        case .TrimStart:
            let latestStart = capture.trimEnd() - 1
            capture.setTrim(Math.min(capture.playheadTime(), latestStart), capture.timeline.outPoint)
            main.timeline?.invalidate()

        case .TrimEnd:
            let earliestEnd = capture.trimStart() + 1
            let finish      = Math.min(Math.max(capture.playheadTime(), earliestEnd), capture.timeline.duration)
            capture.setTrim(capture.timeline.inPoint, finish)
            main.timeline?.invalidate()

        case .KeepAll:
            capture.setTrim(0, 0)
            main.timeline?.invalidate()
        }

        return true
    }
}
