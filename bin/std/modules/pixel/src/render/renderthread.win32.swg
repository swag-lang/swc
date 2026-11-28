#global if #os == Swag.TargetOs.Windows

using Core, Win32

impl RenderThread
{
    // Borrows the manual-reset completion handle for integration with a native message wait.
    //
    // The caller must neither close nor signal nor reset it. It is null before start and after close.
    mtd const win32CompletionHandle()->HANDLE? => .completed.handle
}
