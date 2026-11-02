#global if #os == Swag.TargetOs.Linux

internal func loadNativeLibrary(path: string)->const *void fail
{
    if not path.count do
        fail Swag.SystemError{"native library path is empty"}
    let nativePath = String.from(path)
    let handle     = Linux.dlopen(nativePath.buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    if not handle
    {
        let error   = Linux.dlerror()
        let message = error ? cast(string, cast(cstring, error)) : "cannot load native library"
        fail Swag.SystemError{Errors.mkString(message)}
    }

    return handle
}

internal func nativeLibrarySymbol(handle: const *void, name: string)->const *void?
{
    let symbolName = String.from(name)
    if not symbolName.buffer do
        return null
    return Linux.dlsym(cast #unconst (*void, handle), symbolName.buffer)
}

internal func closeNativeLibrary(handle: const *void)
{
    discard Linux.dlclose(cast #unconst (*void, handle))
}
