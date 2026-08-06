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
}

enum EditorTheme
{
    Dark
    Light
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

#[Swag.Using(Properties)]
struct EditorOptions
{
    #[Description("Show text labels in the main toolbar")]
    showToolBarLabels = false

    #[Description("Mask everything outside the selected capture area")]
    clipToSelection = false

    #[Description("Require confirmation before overwriting a capture-linked image")]
    confirmLinkedOverwrite = true

    #[Description("Minimize the editor instead of closing it")]
    hideOnClose = true

    #[Description("sCapture theme")]
    theme: EditorTheme = Dark

    #[Description("Language of the user interface")]
    language: EditorLanguage = .English

    // Transparent means the editor follows the theme, which is what it does until somebody
    // picks a color: a matte fixed in the options stays dark when the interface turns white,
    // and the one surface the application exists to show is then framed by the wrong theme.
    // The picker is opaque, so it can never produce this value by accident.
    #[Description("Background color of the capture editing window, or transparent to follow the theme"), Opaque]
    editBackColor: Color = 0
}
