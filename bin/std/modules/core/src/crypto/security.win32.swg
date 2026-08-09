#global if WINDOWS
#global public
#global namespace Crypto

using Win32

internal func randomFillNative(buffer: *u8, size: u32)->bool
{
    return RtlGenRandom(buffer, size) != 0
}

// Overwrites every byte occupied by `buffer` before returning.
//
// This operation uses a platform routine whose writes are not removed as dead stores.
func(T) secureClear(buffer: [..] T)
{
    const elementSize = #sizeof(T)
    let byteCount = @countof(buffer) * elementSize
    if byteCount do
        discard RtlZeroMemory(@dataof(buffer), byteCount)
}
