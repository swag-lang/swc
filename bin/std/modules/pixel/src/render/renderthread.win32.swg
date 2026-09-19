#global if #os == Swag.TargetOs.Windows

using Core, Win32

impl RenderThread
{
    // Reports whether another frame can start without waiting for presentation.
    //
    // Before start and after close this returns true. It never consumes the completion signal.
    public mtd isReady()->bool => not .isStarted() or (expect WaitForSingleObject(.completed.handle, 0)) == WAIT_OBJECT_0

    // Borrows the manual-reset completion handle for integration with a native message wait.
    //
    // The caller must neither close nor signal nor reset it. It is null before start and after close.
    #[Swag.NoDoc]
    public mtd const win32CompletionHandle()->HANDLE? => .completed.handle
}
