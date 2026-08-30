#global private

func pick(values: const [..] s32, idx: s32)->s32
{
    return values[idx]
}

func byteChecksum(values: const [..] u8)->u32
{
    var result: u32
    for value in values do
        result += cast(u32) value
    return result
}

func containsRune(values: const [..] rune, what: rune)->bool
{
    for value in values where value == what do
        return true
    return false
}

func aggregateLiteralRuneSlice(marker: rune)->bool
{
    return containsRune([marker], marker)
}

struct ProductLine
{
    sku: string
    qty: s32
}

func totalQty(lines: const [..] ProductLine)->s32
{
    var result: s32
    for line in lines do
        result += line.qty
    return result
}

#test
{
    const s: const [..] s32 = [1, 2, 3]
    #assert(s[0] == 1)
    #assert(s[2] == 3)

    const a:    [3] s32        = [4, 5, 6]
    const view: const [..] s32 = a
    Swag.assert(pick(a, 2) == 6)
    Swag.assert(pick([10, 20, 30], 1) == 20)
    Swag.assert(view.count == 3)
    Swag.assert(view[1] == 5)
}

#test
{
    const values: const [..] s32 = [10, 20, 30, 40, 50]
    let mid  = values[1 to 3]
    let tail = mid[1 to]

    Swag.assert(mid.count == 3)
    Swag.assert(mid[0] == 20)
    Swag.assert(mid[2] == 40)
    Swag.assert(tail.count == 2)
    Swag.assert(tail[0] == 30)
    Swag.assert(tail[1] == 40)
}

#test
{
    let text: string = "const"
    let bytes        = cast(const [..] u8) text
    let head         = bytes[until 3]
    let tail         = bytes[2 to]

    Swag.assert(head.count == 3)
    Swag.assert(head[0] == 'c'u8)
    Swag.assert(head[2] == 'n'u8)
    Swag.assert(tail.count == 3)
    Swag.assert(tail[0] == 'n'u8)
    Swag.assert(tail[2] == 't'u8)
}

#test
{
    const emptyText  = ""
    const emptyBytes = cast(const [..] u8) emptyText

    Swag.assert(emptyBytes.count == 0)
    Swag.assert(byteChecksum(emptyBytes) == 0'u32)
}

#test
{
    Swag.assert(aggregateLiteralRuneSlice('\u00E9'rune))
}

#test
{
    const lines: [2] ProductLine =
        [
        {sku: "keyboard", qty: 1},
        {sku: "cable",    qty: 3}
        ]

    const view: const [..] ProductLine = lines
    Swag.assert(view.count == 2)
    Swag.assert(view[0].sku == "keyboard")
    Swag.assert(view[1].sku == "cable")
    Swag.assert(view[1].qty == 3)
    Swag.assert(totalQty(lines) == 4)
}
