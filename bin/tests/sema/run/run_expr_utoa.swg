#global fileprivate
/*
func utoaCopy(result: [*] u8, value: u64)->[*] u8
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

func utoaTestZero()->bool
{
    var buf: [32] u8
    let End = utoaCopy(&buf[0], 0'u64)
    return End == &buf[1] and
        buf[0] == '0' and
        buf[1] == 0
}

func utoaTestValue()->bool
{
    var buf: [32] u8
    let End = utoaCopy(&buf[0], 1234567890'u64)
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

func utoaTestLarge()->bool
{
    var buf: [32] u8
    let End = utoaCopy(&buf[0], 18446744073709551615'u64)
    return End == &buf[20] and
        buf[0] == '1' and
        buf[1] == '8' and
        buf[2] == '4' and
        buf[3] == '4' and
        buf[4] == '6' and
        buf[5] == '7' and
        buf[6] == '4' and
        buf[7] == '4' and
        buf[8] == '0' and
        buf[9] == '7' and
        buf[10] == '3' and
        buf[11] == '7' and
        buf[12] == '0' and
        buf[13] == '9' and
        buf[14] == '5' and
        buf[15] == '5' and
        buf[16] == '1' and
        buf[17] == '6' and
        buf[18] == '1' and
        buf[19] == '5' and
        buf[20] == 0
}

#test
{
    const Ok = #run utoaTestZero()
    #assert(Ok)
}

#test
{
    const Ok = #run utoaTestValue()
    #assert(Ok)
}

#test
{
    const Ok = #run utoaTestLarge()
    #assert(Ok)
}
*/