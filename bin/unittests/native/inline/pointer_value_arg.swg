#global private

#[Swag.Inline]
func inlineCopy(dest: [*] void, src: const [*] void, size: u64)
{
    if size do
        @memcpy(dest, src, size)
}

func copyWithRuntimeTypeSize(dest: [*] void, src: const [*] void, valueType: typeinfo)
{
    let size = valueType.sizeof
    inlineCopy(dest, src, size)
}

#test
{
    var src: [3] s32
    var dst: [3] s32
    src[0] = 10
    src[1] = 20
    src[2] = 30

    let dest = cast([*] u8) &dst[0]
    let from = cast([*] u8) &src[1]
    let size = #sizeof(s32)

    inlineCopy(dest, from, size)
    @assert(dst[0] == 20)
}

#test
{
    var src: [2] s32
    var dst: [2] s32
    src[0] = 10
    src[1] = 20

    let dest = cast([*] u8) &dst[0]
    let from = cast([*] u8) &src[1]

    copyWithRuntimeTypeSize(dest, from, #typeof(s32))
    @assert(dst[0] == 20)
}
