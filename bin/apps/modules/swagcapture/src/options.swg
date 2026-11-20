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

// How much of the picture a video keeps: every sample, a sharp picture in a file a few hours can
// afford, or the smallest file.
enum VideoQuality
{
    Maximum
    Balanced
    Compact
}

impl VideoQuality
{
    mtd next()->VideoQuality
    {
        switch #complete me
        {
        case .Maximum:  return .Balanced
        case .Balanced: return .Compact
        case .Compact:  return .Maximum
        }
    }

    // Returns the name the interface shows for this quality.
    mtd label()->string
    {
        switch #complete me
        {
        case .Maximum:  return appStrings().prop_QualityMaximum
        case .Balanced: return appStrings().prop_QualityBalanced
        case .Compact:  return appStrings().prop_QualityCompact
        }
    }

    mtd quantizationQp()->u32
    {
        switch #complete me
        {
        case .Maximum:  return 0
        case .Balanced: return 22
        case .Compact:  return 28
        }
    }
}

// Where a new still image goes after the grab.
enum PictureDestination
{
    Clipboard

    #[Properties.Name("Annotate in Place")]
    InPlace

    #[Properties.Name("Open Editor")]
    Editor
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

    // Kept in the old record so existing settings can seed the separately stored destination.
    #[Hidden, Serialization.Key("sendToEditor")]
    legacySendToEditor = true

    #[Hidden, Serialization.Key("inPlaceEdit")]
    legacyInPlaceEdit = true

    #[Description("Choose what happens after an image capture"), Serialization.NoSerialize]
    pictureDestination: PictureDestination = .InPlace

    #[Description("Reopen the hub after copying an image capture started there")]
    returnToHubAfterCopy = false

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

    #[Description("Keep every pixel, balance detail and file size, or make the smallest file")]
    recordVideoQuality: VideoQuality = .Balanced

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

// What Swag Capture puts on screen when it starts, and when its notification-area icon is
// activated.
//
// The order is the stored one, as for [[EditorLanguage]].
enum StartupMode
{
    Hub     // The floating list of captures to take, with the recent ones.

    #[Properties.Name("Notification Area")]
    Tray     // Nothing: the application waits behind its notification-area icon.

    Editor     // The editor, on the last capture.
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

    #[Description("Choose what opens when Swag Capture starts")]
    startup: StartupMode = .Hub

    #[Description("Show a reminder when Swag Capture continues in the notification area")]
    showResidentNotice = true

    // Retained for compatibility with saved options from the former three-notice limit.
    #[Hidden]
    residentNotices: s32 = 3

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
