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
