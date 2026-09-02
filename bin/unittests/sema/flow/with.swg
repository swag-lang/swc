#global private

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
    Blue
}

struct SemaWithPoint
{
    x: s32
    y: s32
}

struct SemaWithHolder
{
    ptr: #null *SemaWithPoint
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

struct SemaWithMemberOwner
{
    point: SemaWithPoint
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
            .value   = 20
        }

        return me.value * 100 + shadow.value
    }
}

impl SemaWithMemberOwner
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

func semaWithRetvalUndefined()->{ a, b: s32 }
{
    with var result: retval = undefined
    {
        .a = 5
        .b = 8
    }

    return result
}

func semaTest001()
{
    var point: SemaWithPoint

    with point = semaWithMakePoint()
    {
        .x += 1
        .add(2)
        Swag.assert(.sum() == 35)
    }

    Swag.assert(point.x == 13)
    Swag.assert(point.y == 22)
}

func semaTest002()
{
    with var point = semaWithMakePoint()
    {
        .x += 5
        .y += 7
    }

    Swag.assert(point.x == 15)
    Swag.assert(point.y == 27)
}

func semaTest003()
{
    var point = semaWithMakePoint()

    with let ptr = &point
    {
        .x += 5
        .y += 7
    }

    Swag.assert(ptr == &point)
    Swag.assert(point.x == 15)
    Swag.assert(point.y == 27)
}

func semaTest004()
{
    var point:  SemaWithPoint
    var holder: SemaWithHolder

    with holder.ptr = &point
    {
        .x = 7
        .add(3)
    }

    Swag.assert(point.x == 10)
    Swag.assert(point.y == 3)
}

func semaTest005()
{
    var point = semaWithMakePoint()
    var ptr   = &point

    with ptr
    {
        .x += 4
        .y += 5
    }

    Swag.assert(point.x == 14)
    Swag.assert(point.y == 25)
}

func semaTest006()
{
    var sum = 0

    using SemaWithColor
    let a = Red
    let b = Blue
    sum += semaWithColorScore(a)
    sum += semaWithColorScore(.Blue)
    if b == Blue do
        sum += 1

    sum += SemaWithNs.bias(1)
    sum += SemaWithNs.bias(2)

    Swag.assert(sum == 21)
}

func semaTest007()
{
    with var pair: { a, b: s32 }
    {
        .a = 8
        .b = 13
    }

    Swag.assert(pair.a == 8)
    Swag.assert(pair.b == 13)
}

func semaTest008()
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

    Swag.assert(point.x == 11)
    Swag.assert(point.y == 22)
}

func semaTest009()
{
    var owner: SemaWithOwner
    Swag.assert(owner.applyShadow() == 1020)
}

func semaTest010()
{
    let pair = semaWithRetval()
    Swag.assert(pair.a == 1)
    Swag.assert(pair.b == 2)
}

func semaTest011()
{
    let pair = semaWithRetvalUndefined()
    Swag.assert(pair.a == 5)
    Swag.assert(pair.b == 8)
}

func semaTest012()
{
    var owner: SemaWithMemberOwner
    owner.point = semaWithMakePoint()
    Swag.assert(owner.applyMemberScope() == 1527)
}

// A 'with' subject is written out again for every member the block reaches, so it names a place.
// A computed value has to be named first: left as an expression it would be evaluated once per
// member, on a different value each time.
func semaWithErr001()
{
    with semaWithMakePoint()     // swc-expected-error {{sema_err_with_needs_a_place}}
    {
        .x += 1
    }
}

func semaWithPointAddr(p: *SemaWithPoint)->*SemaWithPoint
{
    return p
}

func semaWithErr002()
{
    var point: SemaWithPoint
    with semaWithPointAddr(&point)     // swc-expected-error {{sema_err_with_needs_a_place}}
    {
        .x += 1
    }
}

// Two nested 'with' blocks whose subjects share a member: the inner one is the innermost subject
// and answers. This used to resolve to the enclosing 'with' instead.
struct SemaWithOuterSubject
{
    value: s32
}

struct SemaWithInnerSubject
{
    value: s32
}

func semaWithNestedPrecedence()->s32
{
    var outer: SemaWithOuterSubject
    var inner: SemaWithInnerSubject

    with outer
    {
        with inner
        {
            .value = 7
        }
    }

    return outer.value * 100 + inner.value
}

#test
{
    Swag.assert(semaWithNestedPrecedence() == 7)
}
