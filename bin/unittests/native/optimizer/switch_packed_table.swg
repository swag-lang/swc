#global private

// Switches that only pick a constant read a table, in constant memory unless
// every entry is a single bit.
// Every key around the cases, holes and far values included, must still give
// the case's value or the default, signed values keeping their sign.

enum Kind
{
    A
    B
    C
    D
    E
}

#[Swag.Optimize(true), Swag.NoInline]
func kindWeight(k: Kind)->u32
{
    switch k
    {
    case .A:
        return 1
    case .B:
        return 4
    case .C:
        return 9
    default:
        return 16
    }
}

#[Swag.Optimize(true), Swag.NoInline]
func digitValue(c: u8)->s32
{
    var r = -1
    switch c
    {
    case '0':
        r = 0
    case '1':
        r = 1
    case '5':
        r = 5
    case '7':
        r = 70
    }
    return r
}

#[Swag.Optimize(true), Swag.NoInline]
func offsetOf(code: u64)->s64
{
    switch code
    {
    case 100:
        return -3
    case 101:
        return 2
    case 103:
        return -1
    case 104:
        return 0
    default:
        return -2
    }
}

#[Swag.Optimize(true), Swag.NoInline]
func flagOf(code: u16)->bool
{
    switch code
    {
    case 7:
        return true
    case 9:
        return true
    case 12:
        return true
    default:
        return false
    }
}

#test
{
    Swag.assert(kindWeight(.A) == 1 and kindWeight(.B) == 4 and kindWeight(.C) == 9)
    Swag.assert(kindWeight(.D) == 16 and kindWeight(.E) == 16)

    for v in 0 until 256
    {
        let c        = cast(u8) v
        var expected = -1's32
        if c == '0' do
            expected = 0
        elif c == '1' do
            expected = 1
        elif c == '5' do
            expected = 5
        elif c == '7' do
            expected = 70
        Swag.assert(digitValue(c) == expected)
    }

    for code in [0'u64, 99, 100, 101, 102, 103, 104, 105, 163, 164, 0xFFFFFFFF, 0x100000064, 0xFFFFFFFFFFFFFFFF]
    {
        var expected = -2's64
        if code == 100 do
            expected = -3
        elif code == 101 do
            expected = 2
        elif code == 103 do
            expected = -1
        elif code == 104 do
            expected = 0
        Swag.assert(offsetOf(code) == expected)
    }

    for v in 0 until 70000
    {
        let code = cast #wrap (u16) v
        Swag.assert(flagOf(code) == (code == 7 or code == 9 or code == 12))
    }
}
