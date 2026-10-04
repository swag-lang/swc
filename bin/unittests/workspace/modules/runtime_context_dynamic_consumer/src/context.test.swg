#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

#[Swag.CallingConvention(.C)]
func readFreshThreadContext(parameter: *void?)->u32
{
    let result = cast(*bool) parameter!
    let first  = Swag.getContext()
    let second = Swag.getContext()
    result[] = first == second and first.allocator != null and first.runtimeTlsIdPlusOne != 0
    let memory = Core.Memory.alloc(48)
    Core.Memory.free(memory, 48)
    return 0
}

// A native callback thread has no context until its first read. Its next read
// must return the same initialized context through the direct TLS path.
#test
{
    if Swag.jit() do return
    var initialized = false
    var threadId: Win32.DWORD
    let thread      = expect Win32.CreateThread(null, 0, &readFreshThreadContext, &initialized, 0, &threadId)
    defer Win32.CloseHandle(thread)
    discard expect Win32.WaitForSingleObject(thread, Win32.INFINITE)
    Swag.assert(initialized)
}
