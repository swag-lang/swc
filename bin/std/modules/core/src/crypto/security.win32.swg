#global if WINDOWS
#global public
#global namespace Crypto

using Win32

internal func randomFillNative(buffer: *u8, size: u32)->bool => RtlGenRandom(buffer, size) != 0

// Overwrites every byte occupied by `buffer` with zero.
//
// The platform routine it calls cannot be removed as a dead store, so the bytes are cleared even
// when `buffer` is never read again.
func(T) secureClear(buffer: [..] T)
{
    const elementSize = #sizeof(T)
    let byteCount = buffer.count * elementSize
    if byteCount do
        discard RtlZeroMemory(buffer.buffer, byteCount)
}
