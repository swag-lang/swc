#global private

func shiftLeftU8ByU64(value: u8, count: u64)->u8  => value << count
func shiftRightU8ByU64(value: u8, count: u64)->u8 => value >> count
func shiftRightS8ByU64(value: s8, count: u64)->s8 => value >> count

func referenceShiftLeftU8(value: u8, count: u64)->u8
{
    var result = value
    for count do result *= #wrap 2'u8
    return result
}

func referenceShiftRightU8(value: u8, count: u64)->u8
{
    var result = value
    for count do result /= 2'u8
    return result
}

func referenceShiftRightS8(value: s8, count: u64)->s8
{
    var result = value
    for count
    {
        if result < 0 and result % 2 != 0 do
            result = result / 2 - 1
        else do
            result /= 2
    }

    return result
}

// Exercise every eight-bit value repeatedly with every valid amount, carried in a count far
// wider than the value: the shift must read the amount at its own width, never narrowed to
// the value's type, and the result must keep the value's type and sign.
#test
{
    for 64
    {
        for rawValue in 256'u32
        {
            let unsignedValue = cast(u8) rawValue
            let signedValue   = cast #wrap (s8) rawValue

            for count in [0'u64, 1, 2, 3, 4, 5, 6, 7]
            {
                Swag.assert(shiftLeftU8ByU64(unsignedValue, count) == referenceShiftLeftU8(unsignedValue, count))
                Swag.assert(shiftRightU8ByU64(unsignedValue, count) == referenceShiftRightU8(unsignedValue, count))
                Swag.assert(shiftRightS8ByU64(signedValue, count) == referenceShiftRightS8(signedValue, count))
            }
        }
    }
}

// A left shift truncates the bits it pushes out of the width; this is not an overflow.
#test
{
    #[Swag.Safety(.Overflow, true)]
    func truncatingLeft(value: u8, count: u64)->u8 => value << count

    Swag.assert(truncatingLeft(0x80'u8, 1'u64) == 0'u8)
    Swag.assert(truncatingLeft(0xFF'u8, 4'u64) == 0xF0'u8)
    Swag.assert(truncatingLeft(0x81'u8, 7'u64) == 0x80'u8)
}

// The compound forms read the amount at its own width as well.
#test
{
    var left:  u8  = 0x81
    var right: s8  = -128
    let count: u64 = 7

    left  <<= count
    right >>= count

    Swag.assert(left == 0x80'u8)
    Swag.assert(right == -1's8)
}
