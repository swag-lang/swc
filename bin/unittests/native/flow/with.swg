#global fileprivate

namespace NativeWithNs
{
    func bias(v: s32)->s32
    {
        return v + 10
    }
}

enum NativeWithColor
{
    Red,
    Blue,
}

struct NativeWithPoint
{
    x: s32
    y: s32
}

struct NativeWithHolder
{
    ptr: *NativeWithPoint
}

struct NativeWithWrapper
{
    holder: NativeWithHolder
}

struct NativeWithShadow
{
    value: s32
}

struct NativeWithOwner
{
    value: s32
}

struct NativeWithMemberOwner
{
    point: NativeWithPoint
}

impl NativeWithPoint
{
    mtd add(v: s32)
    {
        me.x += v
        me.y += v * 2
    }

    mtd sum()->s32
    {
        return me.x + me.y
    }
}

impl NativeWithOwner
{
    mtd applyShadow()->s32
    {
        var shadow: NativeWithShadow
        with shadow
        {
            me.value = 4
            .value = 9
        }

        return me.value * 100 + shadow.value
    }
}

impl NativeWithMemberOwner
{
    mtd applyMemberScope()->s32
    {
        with me.point
        {
            .x += 5
            .y += 7
        }

        return me.point.x * 100 + me.point.y
    }
}

func nativeWithMakePoint(x, y: s32)->NativeWithPoint
{
    var result: NativeWithPoint
    result.x = x
    result.y = y
    return result
}

func nativeWithColorScore(c: NativeWithColor)->s32
{
    if c == .Red do
        return 3
    return 7
}

func nativeWithValueAndPointer()->s32
{
    var point = nativeWithMakePoint(1, 2)
    with point
    {
        .add(3)
    }

    var ptr = &point
    with ptr
    {
        .x += 5
        .y += 7
    }

    return point.sum()
}

func nativeWithAssignmentsAndScopes()->s32
{
    var point = nativeWithMakePoint(2, 4)
    var ptr: *NativeWithPoint
    var holder: NativeWithHolder
    var total = 0

    with ptr = &point
    {
        .x += 1
        .y += 2
    }

    with holder.ptr = &point
    {
        .x += 1
        .y += 2
    }

    with NativeWithColor
    {
        let a = Red
        let b = .Blue
        total += nativeWithColorScore(a)
        total += nativeWithColorScore(.Blue)
        if b == Blue do
            total += 1
    }

    with NativeWithNs
    {
        total += bias(2)
        total += .bias(0)
    }

    return point.x + point.y + total
}

func nativeWithAssignedValueTarget()->s32
{
    var point: NativeWithPoint
    with point = nativeWithMakePoint(10, 20)
    {
        .x += 1
        .y += 2
    }

    return point.x * 100 + point.y
}

func nativeWithAnonymous()->s32
{
    with var pair: { a, b: s32 }
    {
        .a = 8
        .b = 13
    }

    return pair.a * 100 + pair.b
}

func nativeWithRetval()->{ a, b: s32 }
{
    with var result: retval
    {
        .a = 21
        .b = 34
    }

    return result
}

func nativeWithRetvalUndefined()->{ a, b: s32 }
{
    with var result: retval = undefined
    {
        .a = 55
        .b = 89
    }

    return result
}

func nativeWithLocalInit()->s32
{
    with var pair = nativeWithRetval()
    {
        .a += 1
        .b += 2
    }

    return pair.a * 100 + pair.b
}

func nativeWithLetPointer()->s32
{
    var point = nativeWithMakePoint(10, 20)
    with let ptr = &point
    {
        .x += 3
        .y += 4
    }

    return ptr.x * 100 + ptr.y
}

func nativeWithNestedMemberTarget()->s32
{
    var point = nativeWithMakePoint(4, 5)
    var wrapper: NativeWithWrapper
    var total = 0
    wrapper.holder.ptr = &point

    with wrapper.holder
    {
        with .ptr
        {
            .x += 1
            total += .x + .y
        }

        with .ptr
        {
            .y += 2
            total += .x + .y
            .x += 3
        }
    }

    return total * 100 + point.x + point.y
}

func nativeWithMeDisambiguation()->s32
{
    var owner: NativeWithOwner
    return owner.applyShadow()
}

#test
{
    @assert(nativeWithValueAndPointer() == 24)
}

#test
{
    @assert(nativeWithAssignmentsAndScopes() == 45)
}

#test
{
    @assert(nativeWithAssignedValueTarget() == 1122)
}

#test
{
    @assert(nativeWithAnonymous() == 813)
}

#test
{
    @assert(nativeWithLocalInit() == 2236)
}

#test
{
    @assert(nativeWithLetPointer() == 1324)
}

#test
{
    @assert(nativeWithNestedMemberTarget() == 2215)
}

#test
{
    @assert(nativeWithMeDisambiguation() == 409)
}

#test
{
    let pair = nativeWithRetval()
    @assert(pair.a == 21)
    @assert(pair.b == 34)
}

#test
{
    let pair = nativeWithRetvalUndefined()
    @assert(pair.a == 55)
    @assert(pair.b == 89)
}

#test
{
    var owner: NativeWithMemberOwner
    owner.point = nativeWithMakePoint(10, 20)
    @assert(owner.applyMemberScope() == 1527)
}
