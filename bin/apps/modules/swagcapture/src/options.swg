// Recording cadences offered by the capture options.
enum AnimationRate
{
    Fps10
    Fps15
    Fps20
}

impl AnimationRate
{
    mtd next()->AnimationRate
    {
        switch #complete me
        {
        case .Fps10: return .Fps15
        case .Fps15: return .Fps20
        case .Fps20: return .Fps10
        }
    }

    mtd framesPerSecond()->u64
    {
        switch #complete me
        {
        case .Fps10: return 10
        case .Fps15: return 15
        case .Fps20: return 20
        }
    }
}

// The capture settings shown in the options grid: what a screenshot includes, how long it waits,
// and where the result goes.
#[Swag.Using(Properties)]
struct CaptureOptions
{
    #[Description("Show a large cross at the mouse position during capture")]
    drawCross = true

    #[Description("Include the mouse cursor in the captured image")]
    captureCursor = false

    #[Description("Temporarily hide the editor before starting the capture")]
    hideEditorBefore = true

    #[Description("Send the captured image to the editor")]
    sendToEditor = true

    #[Description("Copy the captured image to the clipboard")]
    sendToClipboard = true

    #[Description("Edit captured area in place")]
    inPlaceEdit = true

    #[Description("Set the delay time, in seconds, before capturing"), Unit("s")]
    delay = 0

    #[Description("Count down three seconds before a recording starts")]
    recordCountdown = false

    #[Description("Record ten, fifteen or twenty frames each second")]
    recordRate: AnimationRate = .Fps15

    #[Description("Record the microphone on its own video sound track")]
    recordMicrophone = false

    #[Description("Record system sound on its own video sound track")]
    recordSystemSound = false

    #[Description("Stop an animation after this many seconds"), SliderMinMax(1, 60), Unit("s")]
    recordMaxSeconds: s32 = 30

    #[Description("Limit the longest side of a recorded animation"), SliderMinMax(320, 3840), Unit("px")]
    recordMaxDimension: s32 = 1920
}

// Languages the interface can present. `English` is the reference wording and the
// default; `System` follows the Windows language when a translation ships for it.
//
// The order is the stored one: options are serialized by value, so an entry moves only
// when every saved configuration is meant to move with it.
enum EditorLanguage
{
    System
    English
    French
}

// The editor settings shown in the options grid, plus the theme and language the menus choose.
#[Swag.Using(Properties)]
struct EditorOptions
{
    #[Description("Mask everything outside the selected capture area")]
    clipToSelection = false

    #[Description("Require confirmation before overwriting a capture-linked image")]
    confirmLinkedOverwrite = true

    #[Description("Minimize the editor instead of closing it")]
    hideOnClose = true

    #[Hidden]
    theme: AppearanceTheme = .Dark

    #[Hidden]
    language: EditorLanguage = .English

    // Transparent means the editor follows the theme, which is what it does until somebody
    // picks a color: a matte fixed in the options stays dark when the interface turns white,
    // and the one surface the application exists to show is then framed by the wrong theme.
    // The picker is opaque, so it can never produce this value by accident.
    #[Description("Background color of the capture editing window, or transparent to follow the theme"), Opaque]
    editBackColor: Color = 0
}
