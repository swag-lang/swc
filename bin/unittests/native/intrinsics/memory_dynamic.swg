#global private

#[Swag.NoInline]
func fillDynamic(target: #null [*] void, value: u8, size: u64)
{
    @memset(target, value, size)
}

#[Swag.NoInline]
func copyDynamic(target: #null [*] void, source: #null const [*] void, size: u64)
{
    @memcpy(target, source, size)
}

#[Swag.NoInline]
func moveDynamic(target: #null [*] void, source: #null const [*] void, size: u64)
{
    @memmove(target, source, size)
}

#[Swag.NoInline]
func compareDynamic(left, right: #null const [*] void, size: u64)->s32
{
    return @memcmp(left, right, size)
}

#test
{
    var source: [17] u8
    var target: [17] u8
    for &value, index in source do
        dref value = cast(u8) (index + 1)

    fillDynamic(target, 0xA5, #sizeof(target))
    for value in target do
        @assert(value == 0xA5)

    copyDynamic(target, source, #sizeof(target))
    @assert(compareDynamic(target, source, #sizeof(target)) == 0)

    target[8] = 0
    @assert(compareDynamic(target, source, #sizeof(target)) < 0)
    target[8] = 0xFF
    @assert(compareDynamic(target, source, #sizeof(target)) > 0)
}

#test
{
    var data: [10] u8 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    moveDynamic(&data[2], &data[0], 7)
    @assert(data == [0, 1, 0, 1, 2, 3, 4, 5, 6, 9])

    moveDynamic(&data[0], &data[2], 7)
    @assert(data == [0, 1, 2, 3, 4, 5, 6, 5, 6, 9])

    moveDynamic(&data[0], &data[0], #sizeof(data))
    fillDynamic(null, 0, 0)
    copyDynamic(null, null, 0)
    moveDynamic(null, null, 0)
    @assert(compareDynamic(null, null, 0) == 0)
}

#test
{
    var data: [96] u8
    for &value, index in data do
        dref value = cast(u8) index

    moveDynamic(&data[8], &data[0], 80)
    for index in 80 do
        @assert(data[8 + index] == cast(u8) index)

    for &value, index in data do
        dref value = cast(u8) index
    moveDynamic(&data[0], &data[8], 80)
    for index in 80 do
        @assert(data[index] == cast(u8) (index + 8))
}
