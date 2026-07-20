#global private

struct Pair32
{
    a: u32
    b: u32
}

func MakePair32()->Pair32
{
    return {a: 20, b: 22}
}

func SumPair32(value: Pair32)->u32
{
    return value.a + value.b
}

#test
{
    @assert(SumPair32(MakePair32()) == 42)
}

#[Swag.Pack(1)]
struct PackedHeader18
{
    idLength:          u8
    colorMapType:      u8
    imageTypeCode:     u8
    colorMapFirst:     u16
    colorMapLength:    u16
    colorMapBpp:       u8
    originX:           u16
    originY:           u16
    width:             u16
    height:            u16
    bpp:               u8
    descriptorByte:    u8
}

struct PackedPointerTarget
{
    width:  s32
    height: s32
    stride: u64
    bpp:    u64
    buffer: [16] u8
}

struct PackedPaletteLike
{
    data:  const [*] u8
    first: u16
    count: u16
    bpp:   u8
    bpp8:  u8
}

struct MiniArrayLike
{
    buffer: [*] u8
    count:  u64
    capacity: u64
}

struct PackedImageLike
{
    pixels: MiniArrayLike
    size:   u64
    width:  s32
    height: s32
    width8: s32
    pf:     u32
    bpp:    u8
    bpp8:   u8
    meta:   MiniArrayLike
    work:   *PackedImageLike
    storage: [16] u8
}

func PackedPointerAfterHeader(result: *PackedPointerTarget, header: PackedHeader18, pixelIndex: u64)->u8
{
    let srcX = cast(s32) (pixelIndex % header.width)
    let dstX = header.descriptorByte & 0x10 ? result.width - srcX - 1 : srcX
    let ofs  = cast(u64) dstX * result.bpp
    return result.buffer[ofs] + header.imageTypeCode
}

func PackedImageDst(result: *PackedImageLike, header: PackedHeader18, pixelIndex: u64)->[*] u8
{
    let srcX = cast(s32) (pixelIndex % header.width)
    let srcY = cast(s32) (pixelIndex / header.width)
    let dstX = header.descriptorByte & 0x10 ? result.width - srcX - 1 : srcX
    let dstY = header.descriptorByte & 0x20 ? result.height - srcY - 1 : srcY
    return result.pixels.buffer + cast(u64) dstY * result.width8 + cast(u64) dstX * result.bpp8
}

func PackedImageWrite(result: *PackedImageLike, header: PackedHeader18, pixelIndex: u64, src: [*] u8)
{
    let dst = PackedImageDst(result, header, pixelIndex)
    dst[0] = src[0]
}

func PackedImageDecodeLike(header: PackedHeader18)->PackedImageLike
{
    var result: retval = undefined
    result.width         = 2
    result.height        = 2
    result.bpp8          = 3
    result.width8        = 6
    result.pixels.buffer = result.storage
    result.pixels.count  = 12
    result.storage[3]    = 42
    PackedImageWrite(&result, header, 1, cast([*] u8) result.storage + 3)
    return result
}

func PackedForwardingCaller(result: *PackedPointerTarget, header: PackedHeader18, palette: PackedPaletteLike, pixelIndex: u64, src: const [*] u8)->u8
{
    return PackedPointerAfterHeader(result, header, pixelIndex) + src[0] - src[0] + cast(u8) palette.count - cast(u8) palette.count
}

func PackedReturnValueCaller(header: PackedHeader18)->PackedPointerTarget
{
    var result: retval
    result.width     = 2
    result.height    = 2
    result.stride    = 6
    result.bpp       = 3
    result.buffer[3] = 40

    var palette: PackedPaletteLike = {data: result.buffer, count: 1}
    result.buffer[0] = PackedForwardingCaller(&result, header, palette, 1, result.buffer)
    return result
}

#test
{
    var target: PackedPointerTarget
    target.width     = 2
    target.height    = 2
    target.stride    = 6
    target.bpp       = 3
    target.buffer[3] = 40

    var header: PackedHeader18
    header.imageTypeCode = 2
    header.width         = 2
    header.height        = 2
    header.bpp           = 24
    @assert(PackedPointerAfterHeader(&target, header, 1) == 42)

    var palette: PackedPaletteLike = {data: target.buffer, count: 1}
    @assert(PackedForwardingCaller(&target, header, palette, 1, target.buffer) == 42)

    let ret = PackedReturnValueCaller(header)
    @assert(ret.buffer[0] == 42)

    let img = PackedImageDecodeLike(header)
    @assert(img.storage[3] == 42)
}
