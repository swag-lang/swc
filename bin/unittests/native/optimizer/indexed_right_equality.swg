#global private

// An indexed byte read is the right operand of the equality test. The
// comparison may use memory directly when the byte is not read again.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func countMatches(bytes: const [*] u8, count: u64, needle: u8)->u64
{
    var matches = 0'u64
    for index in count
    {
        if needle == bytes[index] do
            matches += 1
    }
    return matches
}

#test
{
    var bytes: [7] u8 = [0, 7, 255, 7, 1, 7, 0]
    Swag.assert(countMatches(&bytes[0], 7, 7) == 3)
    Swag.assert(countMatches(&bytes[0], 7, 0) == 2)
    Swag.assert(countMatches(&bytes[0], 7, 9) == 0)
    Swag.assert(countMatches(&bytes[0], 3, 7) == 1)
}
