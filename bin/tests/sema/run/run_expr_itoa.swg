#global fileprivate

func itoaCopy(result: [*] u8, value: s64)->[*] u8
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

func itoaTestZero()->bool
{
    var buf: [32] u8
    let End = itoaCopy(&buf[0], 0's64)
    return End == &buf[1] and
        buf[0] == '0' and
        buf[1] == 0
}

func itoaTestPositive()->bool
{
    var buf: [32] u8
    let End = itoaCopy(&buf[0], 1234567890's64)
    return End == &buf[10] and
        buf[0] == '1' and
        buf[1] == '2' and
        buf[2] == '3' and
        buf[3] == '4' and
        buf[4] == '5' and
        buf[5] == '6' and
        buf[6] == '7' and
        buf[7] == '8' and
        buf[8] == '9' and
        buf[9] == '0' and
        buf[10] == 0
}

func itoaTestNegative()->bool
{
    var buf: [32] u8
    let End = itoaCopy(&buf[0], -987654321's64)
    return End == &buf[10] and
        buf[0] == '-' and
        buf[1] == '9' and
        buf[2] == '8' and
        buf[3] == '7' and
        buf[4] == '6' and
        buf[5] == '5' and
        buf[6] == '4' and
        buf[7] == '3' and
        buf[8] == '2' and
        buf[9] == '1' and
        buf[10] == 0
}

#test
{
    const Ok = #run itoaTestZero()
    #assert(Ok)
}

#test
{
    const Ok = #run itoaTestPositive()
    #assert(Ok)
}

#test
{
    const Ok = #run itoaTestNegative()
    #assert(Ok)
}
