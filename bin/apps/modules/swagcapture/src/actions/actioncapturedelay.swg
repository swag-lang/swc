using Gui

// The commands that choose how many seconds a capture waits before it is taken.
struct ActionCaptureDelay {}

impl ActionCaptureDelay
{
    newCmdId("Delay")
    newCmdId("Delay0")
    newCmdId("Delay3")
    newCmdId("Delay5")
    newCmdId("Delay10")
}

// One wait the capture menu offers: its seconds and the command that chooses it.
struct CaptureDelayChoice
{
    seconds: s32
    id:      WndId
}

// The waits the capture menu offers. Any other number can still be set in the options, and the
// menu names it all the same.
const CaptureDelays: [4] CaptureDelayChoice = [{0, ActionCaptureDelay.Delay0}, {3, ActionCaptureDelay.Delay3}, {5, ActionCaptureDelay.Delay5}, {10, ActionCaptureDelay.Delay10}]

// Returns the words naming a wait of `seconds`: "No Delay", or "5 Seconds".
func captureDelayName(seconds: s32)->String
{
    if seconds <= 0 do
        return appStrings().act_NoDelay
    return MainWnd.countWords(appStrings().count_Seconds, cast(u64, seconds))
}

impl IActionUI for ActionCaptureDelay
{
    acceptOwnCmdIds()

    // The menu entry names the wait in force; its choices name their own, the one in force
    // checked. Every one carries the hourglass, as every command of the lens has its glyph.
    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main  = mainWndOf(cxt)
        let delay = main.captureOptions.delay
        if cxt.id == ActionCaptureDelay.Delay
        {
            evt.updatedFields |= .Icon | .Name
            evt.icon          = cxt.wnd!.theme().icon(.HourGlass)
            evt.name          = delay == 0 ? appStrings().act_DelayBefore : Format.toString(appStrings().act_DelayDuration, captureDelayName(delay))
            return true
        }

        for choice in CaptureDelays where choice.id == cxt.id
        {
            evt.updatedFields |= .Icon | .Name | .Checked | .RenderingHint
            evt.icon          = cxt.wnd!.theme().icon(.HourGlass)
            evt.renderingHint = .ExclusiveGroup
            evt.name          = captureDelayName(choice.seconds)
            evt.checked       = delay == choice.seconds
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = mainWndOf(cxt)
        for choice in CaptureDelays where choice.id == cxt.id do
            main.captureOptions.delay = choice.seconds
        return true
    }
}
