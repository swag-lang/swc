#global private

struct ByteBox
{
    values: [2] u8
}

impl ByteBox
{
    mtd const opIndex(index: u64)->u8
    {
        return .values[index]
    }

    mtd opIndexSet(index: u64, value: u8)
    {
        .values[index] = value
    }
}

func arrayShift0(values: &[2] u8, shift: s64)->s64
{
    return values[0] + shift
}

func boxShift0(values: &ByteBox, shift: s64)->s64
{
    return values[0] + shift
}

#test
{
    var values: [2] u8 = [0, 1]
    let shift = 482's64

    @assert(values[0] == 0'u8)
    @assert(values[1] == 1'u8)
    @assert(arrayShift0(&values, shift) == 482's64)
    @assert(cast(u8) ((values[0] + shift) % 26 + 'a') == 'o')
}

#test
{
    var values = ByteBox{values: [0, 1]}
    let shift  = 482's64

    @assert(values[0] == 0'u8)
    @assert(values[1] == 1'u8)
    @assert(boxShift0(&values, shift) == 482's64)
    @assert(cast(u8) ((values[0] + shift) % 26 + 'a') == 'o')
}
