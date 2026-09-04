#global private

// The source language always initializes storage safely. SemaInitFlow may remove
// that default only after proving that every field is assigned before a read,
// escape, drop, or control-flow merge can observe it.

struct FlowPod
{
    a: s32
    b: s32
    c: s32
}

struct FlowDrop
{
    value: s32
}

var g_flowDropCount: s32

impl FlowDrop
{
    mtd opDrop()
    {
        g_flowDropCount += 1
    }
}

func makeFlowDrop(value: s32)->FlowDrop
{
    var result: retval
    result.value = value
    return result
}

func flowPartialRead()->s32
{
    var value: FlowPod
    value.a = 1
    return value.b
}

func flowEscapedRead()->s32
{
    var value: FlowPod
    return flowReadThroughPointer(&value)
}

func flowReadThroughPointer(value: *FlowPod)->s32 => value.b

func flowCompleteRetval()->FlowPod
{
    var result: retval
    result.a = 1
    result.b = 2
    result.c = 3
    return result
}

#test
{
    // An incomplete write keeps the safe default for the unread field.
    Swag.assert(flowPartialRead() == 0)
}

#test
{
    // Taking an address is deliberately conservative: the callee can observe the
    // default before it writes anything.
    Swag.assert(flowEscapedRead() == 0)
}

#test
{
    let value = flowCompleteRetval()
    Swag.assert(value.a == 1 and value.b == 2 and value.c == 3)
}

#test
{
    // A whole-value assignment remains safe even when the type has a lifecycle:
    // the optimizer must preserve any observable default and drop.
    g_flowDropCount = 0
    {
        var value: FlowDrop
        value = makeFlowDrop(7)
        Swag.assert(value.value == 7)
    }
    Swag.assert(g_flowDropCount == 1)
}
