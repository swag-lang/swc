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
