#global fileprivate

// Real-life example: a workflow combines three structs that customize direct
// assignment, compound assignment, and indexed access.

struct WorkflowSource
{
    value: s32
}

struct WorkflowTarget
{
    value: s32
    tag:   s32
    calls: s32
}

impl WorkflowTarget
{
    #[Swag.NoInline]
    mtd opSet(value: s32)
    {
        .value = value
        .tag = 10
        .calls += 1
    }

    #[Swag.NoInline]
    mtd opSet(source: WorkflowSource)
    {
        .value = source.value + 5
        .tag = 20
        .calls += 1
    }
}

struct WorkflowAssignBox
{
    a:     s32
    b:     s32
    calls: s32
}

impl WorkflowAssignBox
{
    #[Swag.NoInline]
    mtd setPair(a, b: s32)
    {
        .a = a
        .b = b
        .calls += 1
    }

    #[Swag.NoInline]
    mtd(op: string) opAssign(value: s32)
    {
        #if op == "+=" do
            .setPair(.a + value, .b + value)
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }

    #[Swag.NoInline]
    mtd(op: string) opAssign(other: const &WorkflowAssignBox)
    {
        #if op == "+=" do
            .setPair(.a + other.a, .b + other.b)
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }
}

struct WorkflowIndexBox
{
    first:  s32
    second: s32
    reads:  s32
    writes: s32
}

impl WorkflowIndexBox
{
    #[Swag.NoInline]
    mtd opIndex(index: s32) -> s32
    {
        .reads += 1
        if index == 0 do
            return .first
        return .second
    }

    #[Swag.NoInline]
    mtd opIndexSet(index: s32, value: s32)
    {
        .writes += 1
        if index == 0 do
            .first = value
        else do
            .second = value
    }
}

struct WorkflowState
{
    target: WorkflowTarget
    accum:  WorkflowAssignBox
    slots:  WorkflowIndexBox
}

// ---------------------------------------------------------------------------
// Combined workflow: all operator overload hooks participate in one state update
// ---------------------------------------------------------------------------

#test
{
    var flow = WorkflowState{
        accum: WorkflowAssignBox{a: 1, b: 2},
        slots: WorkflowIndexBox{first: 10, second: 20},
    }

    flow.target = 7's32
    let source = WorkflowSource{value: 5}
    flow.target = source

    flow.accum += 3's32
    let bonus = WorkflowAssignBox{a: 4, b: 6}
    flow.accum += bonus

    flow.slots[1] = flow.accum.a
    let total = flow.slots[0] + flow.slots[1]

    @assert(flow.target.value == 10)
    @assert(flow.target.tag == 20)
    @assert(flow.target.calls == 2)
    @assert(flow.accum.a == 8)
    @assert(flow.accum.b == 11)
    @assert(flow.accum.calls == 2)
    @assert(flow.slots.first == 10)
    @assert(flow.slots.second == 8)
    @assert(flow.slots.writes == 1)
    @assert(flow.slots.reads == 2)
    @assert(total == 18)
}

// ---------------------------------------------------------------------------
// Secondary example: values flow from set/assign into indexed storage
// ---------------------------------------------------------------------------

#test
{
    var flow = WorkflowState{}

    flow.target = 42's32
    flow.accum += 5's32
    flow.slots[0] = flow.target.value + flow.accum.a
    let first = flow.slots[0]
    let second = flow.slots[1]

    @assert(flow.target.value == 42)
    @assert(flow.target.tag == 10)
    @assert(flow.accum.a == 5)
    @assert(flow.accum.b == 5)
    @assert(flow.accum.calls == 1)
    @assert(flow.slots.first == 47)
    @assert(flow.slots.writes == 1)
    @assert(flow.slots.reads == 2)
    @assert(first == 47)
    @assert(second == 0)
}
