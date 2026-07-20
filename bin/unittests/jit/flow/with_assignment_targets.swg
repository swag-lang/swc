#global private

namespace JitWithAssignNs
{
    func bias(v: s32)->s32
    {
        return v + 10
    }
}

enum JitWithAssignColor
{
    Red,
    Blue,
}

struct JitWithAssignPoint
{
    x: s32
    y: s32
}

struct JitWithAssignHolder
{
    ptr: *JitWithAssignPoint
}

struct JitWithAssignWrapper
{
    holder: JitWithAssignHolder
}

struct JitWithAssignShadow
{
    value: s32
}

struct JitWithAssignOwner
{
    value: s32
}

struct JitWithAssignMemberOwner
{
    point: JitWithAssignPoint
}

func jitWithAssignMakePoint(x, y: s32)->JitWithAssignPoint
{
    var result: JitWithAssignPoint
    result.x = x
    result.y = y
    return result
}

func jitWithAssignColorScore(c: JitWithAssignColor)->s32
{
    if c == .Red do
        return 3
    return 7
}

impl JitWithAssignOwner
{
    mtd applyShadow()->s32
    {
        var shadow: JitWithAssignShadow
        with shadow
        {
            me.value = 4
            .value = 9
        }

        return me.value * 100 + shadow.value
    }
}

impl JitWithAssignMemberOwner
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

func jitWithValueAndPointer()->s32
{
    var point = jitWithAssignMakePoint(1, 2)
    with point
    {
        .x += 3
        .y += 6
    }

    var ptr = &point
    with ptr
    {
        .x += 5
        .y += 7
    }

    return point.x * 100 + point.y
}

func jitWithAssignedValueTarget()->s32
{
    var point: JitWithAssignPoint
    with point = jitWithAssignMakePoint(10, 20)
    {
        .x += 1
        .y += 2
    }

    return point.x * 100 + point.y
}

func jitWithAssignmentsAndScopes()->s32
{
    var point = jitWithAssignMakePoint(2, 4)
    var ptr: *JitWithAssignPoint = undefined
    var holder: JitWithAssignHolder = undefined
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

    with JitWithAssignColor
    {
        let a = Red
        let b = .Blue
        total += jitWithAssignColorScore(a)
        total += jitWithAssignColorScore(.Blue)
        if b == Blue do
            total += 1
    }

    with JitWithAssignNs
    {
        total += bias(2)
        total += .bias(0)
    }

    return point.x + point.y + total
}

func jitWithNestedMemberTarget()->s32
{
    var point = jitWithAssignMakePoint(4, 5)
    var wrapper: JitWithAssignWrapper = undefined
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

func jitWithMeDisambiguation()->s32
{
    var owner: JitWithAssignOwner
    return owner.applyShadow()
}

// A `with` block must shadow the enclosing receiver `me`, including when both the
// `with` target's type and `me`'s type expose a method with the SAME name: inside
// the block `.bump()` must call the with-target's method, not `me`'s. Regression:
// member-access / pointer-field / assignment `with` targets used to lose to `me`
// (the receiver was ranked above the auto-member binding), so `.bump()` wrongly
// called me.bump() — e.g. the Properties color-array editor disabled the whole
// control instead of its own edit box.
struct JitWithPrioInner
{
    hits: s32
}

impl JitWithPrioInner
{
    mtd bump()
    {
        .hits += 100
    }
}

struct JitWithPrioOwner
{
    inner:  JitWithPrioInner
    pInner: #null *JitWithPrioInner
    hits:   s32
}

impl JitWithPrioOwner
{
    mtd bump()
    {
        .hits += 1
    }

    // with a member-access target
    mtd viaMember()->s32
    {
        with .inner { .bump() }
        return .hits * 1000 + .inner.hits
    }

    // with a pointer member target
    mtd viaPointer(target: *JitWithPrioInner)->s32
    {
        .pInner = target
        with .pInner { .bump() }
        return .hits * 1000 + target.hits
    }

    // with an assignment-to-member target (the array.swg shape)
    mtd viaAssign(target: *JitWithPrioInner)->s32
    {
        with .pInner = target { .bump() }
        return .hits * 1000 + target.hits
    }
}

#test
{
    const value = #run
    {
        var owner: JitWithPrioOwner
        return owner.viaMember()
    }
    @assert(value == 100)   // inner.bump ran (hits 100); me.bump did NOT (hits 0)
}

#test
{
    const value = #run
    {
        var owner:  JitWithPrioOwner
        var target: JitWithPrioInner
        return owner.viaPointer(&target)
    }
    @assert(value == 100)
}

#test
{
    const value = #run
    {
        var owner:  JitWithPrioOwner
        var target: JitWithPrioInner
        return owner.viaAssign(&target)
    }
    @assert(value == 100)
}

#test
{
    const value = #run jitWithValueAndPointer()
    @assert(value == 915)
}

#test
{
    const value = #run jitWithAssignedValueTarget()
    @assert(value == 1122)
}

#test
{
    const value = #run jitWithAssignmentsAndScopes()
    @assert(value == 45)
}

#test
{
    const value = #run jitWithNestedMemberTarget()
    @assert(value == 2215)
}

#test
{
    const value = #run jitWithMeDisambiguation()
    @assert(value == 409)
}

#test
{
    const value = #run
    {
        var owner: JitWithAssignMemberOwner
        owner.point = jitWithAssignMakePoint(10, 20)
        return owner.applyMemberScope()
    }

    @assert(value == 1527)
}
