#global private

struct Empty {}

#[Swag.NoInline]
func runtimeByte(value: u8)->u8 => value

// Runtime tuples retain their aggregate layout, including padding and skipped fields.
#test
{
    let {head, ?, wide, ?, tail} = {
        runtimeByte(3), Empty{}, cast(u64) runtimeByte(11) << 40,
        cast(u16) runtimeByte(17), runtimeByte(23)}
    Swag.assert(head == 3)
    Swag.assert(wide == 11'u64 << 40)
    Swag.assert(tail == 23)
}

// Named patterns can move backwards through the source layout.
#test
{
    let {tail: last, word: middle, wide: big, head: first} = {
        head: runtimeByte(5), wide: cast(u64) runtimeByte(13) << 40,
        word: cast(u16) runtimeByte(19), tail: runtimeByte(29)}
    Swag.assert(first == 5)
    Swag.assert(big == 13'u64 << 40)
    Swag.assert(middle == 19)
    Swag.assert(last == 29)
}

#test
{
    var head, tail: u8
    var wide:       u64
    var word:       u16
    {head, ?, wide, word, tail} = {
        runtimeByte(7), Empty{}, cast(u64) runtimeByte(17) << 40,
        cast(u16) runtimeByte(31), runtimeByte(37)}
    Swag.assert(head == 7)
    Swag.assert(wide == 17'u64 << 40)
    Swag.assert(word == 31)
    Swag.assert(tail == 37)

    {tail: tail, word: word, wide: wide, head: head} = {
        head: runtimeByte(11), wide: cast(u64) runtimeByte(19) << 40,
        word: cast(u16) runtimeByte(41), tail: runtimeByte(43)}
    Swag.assert(head == 11)
    Swag.assert(wide == 19'u64 << 40)
    Swag.assert(word == 41)
    Swag.assert(tail == 43)
}
