#global if WINDOWS
#global public
#global namespace Crypto

using Win32

// Fills `buffer` with bytes from the operating system cryptographic random-number generator.
func randomBytes(buffer: [..] u8) fail
{
    var done = 0'u64
    while done < @countof(buffer)
    {
        let chunk = cast(u32) Math.min(@countof(buffer) - done, cast(u64) Swag.U32.Max)
        if BCryptGenRandom(null, @dataof(buffer) + done, chunk, BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0 do
            fail Swag.SystemError{"the operating system cryptographic random-number generator failed"}
        done += chunk
    }
}

// Overwrites every byte occupied by `buffer` before returning.
//
// This operation uses a platform routine whose writes are not removed as dead stores.
func(T) secureClear(buffer: [..] T)
{
    const elementSize = #sizeof(T)
    let byteCount     = @countof(buffer) * elementSize
    if byteCount do
        discard RtlZeroMemory(@dataof(buffer), byteCount)
}
