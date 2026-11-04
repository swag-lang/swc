#global if #os == Swag.TargetOs.Linux
#global namespace Time

#[Swag.CallingConvention(.C)]
private func timerThreadEntryNative(param: *void?)->*void?
{
    discard timerWorkerEntry(param)
    return null
}

private func createTimerThreadNative(param: *void)->const *void fail
{
    var thread: Linux.pthread_t
    let error = Linux.pthread_create(&thread, null, &timerThreadEntryNative, param)
    if error != 0 do
        try Errors.failLinuxError(error)
    return cast(const *void, thread)
}

private func joinTimerThreadNative(handle: const *void?)
{
    let error = Linux.pthread_join(cast(u64, unwrap handle), null)
    if error != 0 do
        Swag.panic("cannot join the timer's worker", #curlocation)
}
