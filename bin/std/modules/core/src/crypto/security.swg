#global public
#global namespace Crypto

// Compares two byte sequences without data-dependent early exit.
//
// Length remains observable: sequences with different lengths return immediately.
func constantTimeEqual(left, right: const [..] u8)->bool
{
    if @countof(left) != @countof(right) do
        return false

    var difference = 0'u8
    for [i] in @countof(left) do
        difference |= left[i] ^ right[i]
    return difference == 0
}

// Fills `buffer` completely from the operating system cryptographic random-number source.
func randomBytes(buffer: [..] u8) fail
{
    var done = 0'u64
    while done < @countof(buffer)
    {
        let chunk = cast(u32) Math.min(@countof(buffer) - done, cast(u64) Swag.U32.Max)
        if !randomFillNative(@dataof(buffer) + done, chunk) do
            fail Swag.SystemError{"the operating system cryptographic random-number generator failed"}
        done += chunk
    }
}
