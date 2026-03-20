#global fileprivate // 

func pick(values: const [..] s32, idx: s32)->s32
{
    return values[idx]
}

func byteChecksum(values: const [..] u8)->u32
{
    var result: u32
    foreach value in values do
        result += cast(u32) value
    return result
}

struct ProductLine
{
    sku: string
    qty: s32
}

func totalQty(lines: const [..] ProductLine)->s32
{
    var result: s32
    foreach line in lines do
        result += line.qty
    return result
}

#test
{
    const s: const [..] s32 = [1, 2, 3]
    #assert(s[0] == 1)
    #assert(s[2] == 3)

    const a: [3] s32 = [4, 5, 6]
    const view: const [..] s32 = a
    @assert(pick(a, 2) == 6)
    @assert(pick([10, 20, 30], 1) == 20)
    @assert(@countof(view) == 3)
    @assert(view[1] == 5)
}

#test
{
    const values: const [..] s32 = [10, 20, 30, 40, 50]
    let mid = values[1 to 3]
    let tail = mid[1 to ]

    @assert(@countof(mid) == 3)
    @assert(mid[0] == 20)
    @assert(mid[2] == 40)
    @assert(@countof(tail) == 2)
    @assert(tail[0] == 30)
    @assert(tail[1] == 40)
}

#test
{
    let text: string = "const"
    let bytes = cast(const [..] u8) text
    let head = bytes[ until 3]
    let tail = bytes[2 to ]

    @assert(@countof(head) == 3)
    @assert(head[0] == 'c''u8)
    @assert(head[2] == 'n''u8)
    @assert(@countof(tail) == 3)
    @assert(tail[0] == 'n''u8)
    @assert(tail[2] == 't''u8)
}

#test
{
    const emptyText = ""
    const emptyBytes = cast(const [..] u8) emptyText

    @assert(@countof(emptyBytes) == 0)
    @assert(byteChecksum(emptyBytes) == 0'u32)
}

#test
{
    const lines: [2] ProductLine =
    [
        {sku: "keyboard", qty: 1},
        {sku: "cable", qty: 3},
    ]

    const view: const [..] ProductLine = lines
    @assert(@countof(view) == 2)
    @assert(view[0].sku == "keyboard")
    @assert(view[1].sku == "cable")
    @assert(view[1].qty == 3)
    @assert(totalQty(lines) == 4)
}
