#global fileprivate

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

func jitWithAssignmentsAndScopes()->s32
{
    var point = jitWithAssignMakePoint(2, 4)
    var ptr: *JitWithAssignPoint
    var holder: JitWithAssignHolder
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
    var wrapper: JitWithAssignWrapper
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
