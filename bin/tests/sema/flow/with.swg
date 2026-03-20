#global fileprivate

namespace SemaWithNs
{
    func bias(v: s32)->s32
    {
        return v + 3
    }
}

enum SemaWithColor
{
    Red,
    Blue,
}

struct SemaWithPoint
{
    x: s32
    y: s32
}

struct SemaWithHolder
{
    ptr: *SemaWithPoint
}

struct SemaWithWrapper
{
    holder: SemaWithHolder
}

struct SemaWithShadow
{
    value: s32
}

struct SemaWithOwner
{
    value: s32
}

impl SemaWithPoint
{
    mtd add(v: s32)
    {
        me.x += v
        me.y += v
    }

    mtd sum()->s32
    {
        return me.x + me.y
    }
}

impl SemaWithOwner
{
    mtd applyShadow()->s32
    {
        var shadow: SemaWithShadow
        with shadow
        {
            me.value = 10
            .value = 20
        }

        return me.value * 100 + shadow.value
    }
}

func semaWithMakePoint()->SemaWithPoint
{
    var result: SemaWithPoint
    result.x = 10
    result.y = 20
    return result
}

func semaWithColorScore(c: SemaWithColor)->s32
{
    if c == .Red do
        return 4
    return 9
}

func semaWithRetval()->{ a, b: s32 }
{
    with var result: retval
    {
        .a = 1
        .b = 2
    }

    return result
}

#test
{
    var point: SemaWithPoint

    with point = semaWithMakePoint()
    {
        .x += 1
        .add(2)
        @assert(.sum() == 35)
    }

    @assert(point.x == 13)
    @assert(point.y == 22)
}

#test
{
    with var point = semaWithMakePoint()
    {
        .x += 5
        .y += 7
    }

    @assert(point.x == 15)
    @assert(point.y == 27)
}

#test
{
    var point: SemaWithPoint
    var holder: SemaWithHolder

    with holder.ptr = &point
    {
        .x = 7
        .add(3)
    }

    @assert(point.x == 10)
    @assert(point.y == 3)
}

#test
{
    var point = semaWithMakePoint()
    var ptr = &point

    with ptr
    {
        .x += 4
        .y += 5
    }

    @assert(point.x == 14)
    @assert(point.y == 25)
}

#test
{
    var sum = 0

    with SemaWithColor
    {
        let a = Red
        let b = .Blue
        sum += semaWithColorScore(a)
        sum += semaWithColorScore(.Blue)
        if b == Blue do
            sum += 1
    }

    with SemaWithNs
    {
        sum += bias(1)
        sum += .bias(2)
    }

    @assert(sum == 21)
}

#test
{
    with var pair: { a, b: s32 }
    {
        .a = 8
        .b = 13
    }

    @assert(pair.a == 8)
    @assert(pair.b == 13)
}

#test
{
    var point = semaWithMakePoint()
    var wrapper: SemaWithWrapper
    wrapper.holder.ptr = &point

    with wrapper.holder
    {
        with .ptr
        {
            .x += 1
        }

        with .ptr
        {
            .y += 2
        }
    }

    @assert(point.x == 11)
    @assert(point.y == 22)
}

#test
{
    var owner: SemaWithOwner
    @assert(owner.applyShadow() == 1020)
}

#test
{
    let pair = semaWithRetval()
    @assert(pair.a == 1)
    @assert(pair.b == 2)
}

#test
{
    var point: SemaWithPoint
    with point
    {
        let inside = .x
    }

    let outside = .x // swc-expected-error {{sema_err_cannot_compute_auto_scope}}
}

#test
{
    with 1 // swc-expected-error {{sema_err_cannot_compute_auto_scope}}
    {
    }
}

#test
{
    with var a, b: s32 // swc-expected-error {{sema_err_not_value_expr}}
    {
    }
}
