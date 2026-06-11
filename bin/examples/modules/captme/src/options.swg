#[Swag.Using(Properties)]
struct CaptureOptions
{
    //#[Name("")]
    {
        #[Properties.Description("Show a large cross at the mouse position during capture")]
        drawCross = true

        #[Properties.Description("Temporarily hide the editor before starting the capture")]
        hideEditorBefore = true

        #[Properties.Description("Send the captured image to the editor")]
        sendToEditor = true

        #[Properties.Description("Copy the captured image to the clipboard")]
        sendToClipboard = true

        #[Properties.Description("Edit captured area in place")]
        inPlaceEdit = true
    }

    #[Properties.Description("Set the delay time, in seconds, before capturing"), Properties.Unit("s")]
    delay = 0
}

enum EditorTheme
{
    Dark
    Light
}

#[Swag.Using(Properties)]
struct EditorOptions
{
    #[Properties.Description("Show text labels in the main toolbar")]
    showToolBarLabels = true

    #[Properties.Description("Mask everything outside the selected capture area")]
    clipToSelection = false

    #[Properties.Description("Require confirmation before overwriting a capture-linked image")]
    confirmLinkedOverwrite = true

    #[Properties.Description("Minimize the editor instead of closing it")]
    hideOnClose = true

    #[Properties.Description("Captme theme")]
    theme: EditorTheme = Dark

    #[Properties.Description("Specify the background color of the capture editing window"), Properties.Opaque]
    editBackColor: Color = 0xFF2E2E2E
}
