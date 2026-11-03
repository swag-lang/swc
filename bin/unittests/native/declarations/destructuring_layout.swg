#global private

struct Empty {}

// Constant named fields retain their values when bound in a different order.
#test
{
    const first, second: u32 = 21
    var {label: name, count: total, ready: active} = {count: first + second, ready: true, label: "constant"}
    Swag.require(name == "constant")
    Swag.require(total == 42)
    Swag.require(active)

    total += 1
    Swag.require(total == 43)
}

#[Swag.NoInline]
func runtimeByte(value: u8)->u8 => value

// Runtime tuples retain their aggregate layout, including padding and skipped fields.
#test
{
    let (head, _, wide, _, tail) = (
        runtimeByte(3), Empty{}, cast(u64, runtimeByte(11)) << 40,
        cast(u16, runtimeByte(17)), runtimeByte(23))
    Swag.require(head == 3)
    Swag.require(wide == 11'u64 << 40)
    Swag.require(tail == 23)
}

// Named patterns can move backwards through the source layout.
#test
{
    let {tail: last, word: middle, wide: big, head: first} = {
        head: runtimeByte(5), wide: cast(u64, runtimeByte(13)) << 40,
        word: cast(u16, runtimeByte(19)), tail: runtimeByte(29)}
    Swag.require(first == 5)
    Swag.require(big == 13'u64 << 40)
    Swag.require(middle == 19)
    Swag.require(last == 29)
}

#test
{
    var head, tail: u8
    var wide:       u64
    var word:       u16
    (head, _, wide, word, tail) = (
        runtimeByte(7), Empty{}, cast(u64, runtimeByte(17)) << 40,
        cast(u16, runtimeByte(31)), runtimeByte(37))
    Swag.require(head == 7)
    Swag.require(wide == 17'u64 << 40)
    Swag.require(word == 31)
    Swag.require(tail == 37)

    {tail: tail, word: word, wide: wide, head: head} = {
        head: runtimeByte(11), wide: cast(u64, runtimeByte(19)) << 40,
        word: cast(u16, runtimeByte(41)), tail: runtimeByte(43)}
    Swag.require(head == 11)
    Swag.require(wide == 19'u64 << 40)
    Swag.require(word == 41)
    Swag.require(tail == 43)
}
