using Gui

struct ActionCaptureDelay {}

impl ActionCaptureDelay
{
    newCmdId("Delay")
    newCmdId("Delay0")
    newCmdId("Delay1")
    newCmdId("Delay2")
    newCmdId("Delay5")
    newCmdId("Delay9")
}

impl IActionUI for ActionCaptureDelay
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = cast(*MainWnd) notnull cxt.wnd
        switch cxt.id
        {
        case .Delay:
            evt.updatedFields |= .Name
            switch main.captureOptions.delay
            {
            case 0: evt.name = appStrings().act_DelayBefore
            case 1: evt.name = appStrings().act_Delay1
            case 2: evt.name = appStrings().act_Delay2
            case 5: evt.name = appStrings().act_Delay5
            case 9: evt.name = appStrings().act_Delay9
            }

        case .Delay0:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_NoDelay
            evt.checked       = main.captureOptions.delay == 0

        case .Delay1:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_OneSecond
            evt.checked       = main.captureOptions.delay == 1

        case .Delay2:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_TwoSeconds
            evt.checked       = main.captureOptions.delay == 2

        case .Delay5:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_FiveSeconds
            evt.checked       = main.captureOptions.delay == 5

        case .Delay9:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_NineSeconds
            evt.checked       = main.captureOptions.delay == 9
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) notnull cxt.wnd
        switch cxt.id
        {
        case .Delay0: main.captureOptions.delay = 0
        case .Delay1: main.captureOptions.delay = 1
        case .Delay2: main.captureOptions.delay = 2
        case .Delay5: main.captureOptions.delay = 5
        case .Delay9: main.captureOptions.delay = 9
        }

        return true
    }
}
