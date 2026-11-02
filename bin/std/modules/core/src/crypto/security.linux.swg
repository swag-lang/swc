#global if #os == Swag.TargetOs.Linux
#global public
#global namespace Crypto

internal func randomFillNative(buffer: *u8, size: u32)->bool
{
    let bytes = cast([*] u8, buffer)
    var done  = 0'u32
    while done < size
    {
        // getentropy fills the whole request, retries interruptions internally, and accepts
        // at most 256 bytes. It waits for the kernel random source to become initialized.
        let count = Math.min(size - done, 256'u32)
        if Linux.getentropy(bytes + done, count) != 0 do
            return false
        done += count
    }

    return true
}

// Overwrites every byte occupied by `buffer` with zero.
//
// The platform routine it calls cannot be removed as a dead store, so the bytes are cleared even
// when `buffer` is never read again.
func(T) secureClear(buffer: [..] T)
{
    const elementSize = #sizeof(T)
    let byteCount = buffer.count * elementSize
    if byteCount do
        Linux.explicit_bzero(buffer.buffer, byteCount)
}
