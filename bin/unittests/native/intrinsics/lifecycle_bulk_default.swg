#global private

alias MaybePointer = *s32?

#[Swag.NoInline, Swag.Optimize(false)]
func zeroOddByteRange(values: [*] u8)
{
    Swag.init(values, 1023)
}

#test
{
    var values: [1026] s32
    for &value in values do
        value[] = 7
    let first = cast([*] s32) &values[1]

    Swag.init(first, 0)
    for value in values do
        Swag.assert(value == 7)

    Swag.init(first, 1)
    Swag.assert(values[0] == 7 and values[1] == 0 and values[2] == 7)

    values[1] = 7
    Swag.init(first, 1024)
    Swag.assert(values[0] == 7 and values[1025] == 7)
    for i in 1024 do
        Swag.assert(values[i + 1] == 0)
}

#test
{
    var values: [1025] u8
    for &value in values do
        value[] = 0xA5

    // The offset and odd byte count exercise both an unaligned base and the final tail.
    let first = cast([*] u8) &values[1]
    Swag.init(first, 1023)
    Swag.assert(values[0] == 0xA5 and values[1024] == 0xA5)
    for i in 1023 do
        Swag.assert(values[i + 1] == 0)
}

#test
{
    var value:    s32 = 17
    var pointers: [4] MaybePointer = [&value, &value, &value, &value]
    Swag.init(cast([*] MaybePointer) &pointers[1], 2)
    Swag.assert(pointers[0] == &value and pointers[3] == &value)
    Swag.assert(pointers[1] == null and pointers[2] == null)
}

#test
{
    var values: [1025] u8
    for &value in values do
        value[] = 0xA5

    zeroOddByteRange(cast([*] u8) &values[1])
    Swag.assert(values[0] == 0xA5 and values[1024] == 0xA5)
    for i in 1023 do
        Swag.assert(values[i + 1] == 0)
}
