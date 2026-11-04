#global if WINDOWS
#global namespace Time

private func createTimerThreadNative(param: *void)->const *void fail
{
    var id: Win32.DWORD
    let thread = try Win32.CreateThread(null, 0, &timerWorkerEntry, param, 0, &id)
    return cast(const *void, unwrap thread)
}

private func joinTimerThreadNative(handle: const *void?)
{
    expect Win32.WaitForSingleObject(handle, Win32.INFINITE)
    Win32.CloseHandle(handle)
}
