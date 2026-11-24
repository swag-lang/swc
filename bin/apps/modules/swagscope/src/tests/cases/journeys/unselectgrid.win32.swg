#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Win32

const HTCAPTION = 2

#[Swag.TestTag("integration.application.journey")]
#test
{
    let state = Testing.tempFilePath("scope-grid-focus-", ".scc")
    defer catch File.delete(state)
    var app: Application
    let workspace = nativeWorkspace(&app, state)
    let surface = unwrap workspace.surface
    surface.show()
    defer surface.destroy()
    workspace.openScene([scopeTestDataPath("sample.cpp"), scopeTestDataPath("viewer.srt")], .SideBySide)
    waitForWorkspace(&app, workspace)

    let frame = surface.wnd
    var point = frame.localToSurface(frame.captionContentRect().center())
    surface.surfaceToScreen(&point)
    let position = (cast(LPARAM, point.x) & 0xffff) | ((cast(LPARAM, point.y) & 0xffff) << 16)
    let window = surface.win32Handle()
    Swag.require(SendMessageW(window, WM_NCHITTEST, 0, position) == HTCAPTION)
    // Complete the press within the native modal move loop, without touching the desktop pointer.
    expect PostMessageW(window, WM_LBUTTONUP, 0, 0)
    discard SendMessageW(window, WM_NCLBUTTONDOWN, HTCAPTION, position)
    Swag.require(workspace.focusOnGrid and workspace.hasFocus())
    Swag.require(workspace.activeDocument().sendComputeCommandStateEvent(ViewerCommands.Close).disabled)
    workspace.selectView(0)
    Swag.require(not workspace.focusOnGrid and workspace.activeDocument().informationCaptionButton.isEnabled())
}
