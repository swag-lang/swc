#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// A record of at most eight bytes returned from several paths, each of which
// sets some of its fields over the declaration's default, is built in one
// register. Every path must return exactly the bytes it wrote over zeros:
// untouched fields, negative fields, a field written twice, a field read back
// before the record is returned, and a four-byte record.

struct Motion
{
    available: bool
    intra:     bool
    refIdx:    s8
    mvX, mvY:  s16
}

struct Small
{
    tag:   u8
    flags: u8
    value: s16
}

#[Swag.Optimize(true), Swag.NoInline]
func motionOf(kind: u32, refIdx: s8, x, y: s16)->Motion
{
    var result: retval
    if kind == 0 do
        return result
    if kind == 1
    {
        result.available = true
        result.intra     = true
        result.refIdx    = -1
        return result
    }

    result.available = true
    result.refIdx    = refIdx
    result.mvX       = x
    result.mvY       = y
    if kind == 3
    {
        result.mvX = y
        if result.refIdx < 0 do
            result.intra = true
    }
    return result
}

#[Swag.Optimize(true), Swag.NoInline]
func smallOf(tag: u8, value: s16)->Small
{
    var result: retval
    result.tag = tag
    if value < 0 do
        result.flags = 0x80
    result.value = value
    return result
}

#test
{
    let none = motionOf(0, 5, 6, 7)
    Swag.assert(not none.available and not none.intra and none.refIdx == 0 and none.mvX == 0 and none.mvY == 0)

    let intra = motionOf(1, 5, 6, 7)
    Swag.assert(intra.available and intra.intra and intra.refIdx == -1 and intra.mvX == 0 and intra.mvY == 0)

    let inter = motionOf(2, 3, -300, 12)
    Swag.assert(inter.available and not inter.intra and inter.refIdx == 3 and inter.mvX == -300 and inter.mvY == 12)

    let swapped = motionOf(3, -2, 40, -41)
    Swag.assert(swapped.available and swapped.intra and swapped.refIdx == -2 and swapped.mvX == -41 and swapped.mvY == -41)

    let positive = smallOf(9, 1234)
    Swag.assert(positive.tag == 9 and positive.flags == 0 and positive.value == 1234)
    let negative = smallOf(0xFF, -2)
    Swag.assert(negative.tag == 0xFF and negative.flags == 0x80 and negative.value == -2)
}
