#global fileprivate
func itoaCopyForFtoa(result: [*] u8, value: s64)->[*] u8
{
    const conv = "zyxwvutsrqponmlkjihgfedcba9876543210123456789abcdefghijklmnopqrstuvwxyz"

    var ptr      = result
    var orgValue = value
    for
    {
        let tmpValue = orgValue
        orgValue /= 10
        dref ptr = conv[35 + (tmpValue - (orgValue * 10))]
        ptr += 1
        if !orgValue do
            break
    }

    if value < 0
    {
        dref ptr = '-'
        ptr += 1
    }

    let retVal = ptr
    dref ptr = 0
    ptr -= 1

    var ptr1 = result
    while ptr1 < ptr
    {
        let tmpChar = dref ptr
        dref ptr = dref ptr1
        ptr -= 1
        dref ptr1 = tmpChar
        ptr1 += 1
    }

    return retVal
}

func ftoaCopy(result: [*] u8, value: f64)
{
    var ipart = cast(s64) value
    var fpart = value - cast(f64) ipart

    var n = result
    if ipart == 0
    {
        if value < 0
        {
            dref n = '-'
            n += 1
        }

        n[0] = '0'
        n += 1
    }
    else do
        n = itoaCopyForFtoa(result, ipart)

    n[0] = '.'
    n += 1

    const AfterFracN = 8
    var afterPoint   = AfterFracN
    if fpart < 0 do
        fpart = -fpart

    var leadingZeros = 0
    while afterPoint
    {
        fpart *= 10
        if fpart < 1 do
            leadingZeros += 1
        afterPoint -= 1
    }

    if leadingZeros == AfterFracN do
        leadingZeros = 0
    while leadingZeros
    {
        n[0] = '0'
        n += 1
        leadingZeros -= 1
    }

    ipart = cast(s64) fpart
    if fpart - ipart > 0.5 do
        ipart += 1
    itoaCopyForFtoa(n, ipart)
}

func ftoaTestZero()->bool
{
    var buf: [64] u8
    ftoaCopy(&buf[0], 0.0)
    return buf[0] == '0' and
        buf[1] == '.' and
        buf[2] == '0' and
        buf[3] == 0
}

func ftoaTestFraction()->bool
{
    var buf: [64] u8
    ftoaCopy(&buf[0], 123.5)
    return buf[0] == '1' and
        buf[1] == '2' and
        buf[2] == '3' and
        buf[3] == '.' and
        buf[4] == '5' and
        buf[5] == '0' and
        buf[6] == '0' and
        buf[7] == '0' and
        buf[8] == '0' and
        buf[9] == '0' and
        buf[10] == '0' and
        buf[11] == '0' and
        buf[12] == 0
}

func ftoaTestNegative()->bool
{
    var buf: [64] u8
    ftoaCopy(&buf[0], -0.25)
    return buf[0] == '-' and
        buf[1] == '0' and
        buf[2] == '.' and
        buf[3] == '2' and
        buf[4] == '5' and
        buf[5] == '0' and
        buf[6] == '0' and
        buf[7] == '0' and
        buf[8] == '0' and
        buf[9] == '0' and
        buf[10] == '0' and
        buf[11] == 0
}

#test
{
    const Ok = #run ftoaTestZero()
    #assert(Ok)
}

#test
{
    const Ok = #run ftoaTestFraction()
    #assert(Ok)
}

#test
{
    const Ok = #run ftoaTestNegative()
    #assert(Ok)
}
