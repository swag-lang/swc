#global private

struct RuntimeValueIndexBox
{
    first:  s32
    second: s32
    reads:  s32
}

impl RuntimeValueIndexBox
{
    #[Swag.NoInline]
    mtd opIndex(index: s32)->s32
    {
        .reads += 1
        if index == 0 do
            return .first
        return .second
    }
}

struct RuntimeRefIndexBox
{
    buffer: [2] s32
    reads:  s32
}

impl RuntimeRefIndexBox
{
    #[Swag.NoInline]
    mtd opIndexPtr(index: s32)->*s32
    {
        .reads += 1
        return &.buffer[index]
    }

    #[Swag.NoInline]
    mtd const opIndexPtr(index: s32)->const *s32
    {
        return &.buffer[index]
    }
}

struct RuntimeMultiIndexBox
{
    values: [4] s32
    reads:  s32
}

impl RuntimeMultiIndexBox
{
    #[Swag.NoInline]
    mtd opIndex(row: s32, col: s32)->s32
    {
        .reads += 1
        return .values[row * 2 + col]
    }
}

struct RuntimeIndexHolder
{
    value: RuntimeValueIndexBox
    refs:  RuntimeRefIndexBox
}

#test
{
    var box = RuntimeValueIndexBox{first: 7, second: 9}
    let a   = box[0]
    let b   = box[1]

    Swag.assert(a == 7)
    Swag.assert(b == 9)
    Swag.assert(box.reads == 2)
}

#test
{
    var box = RuntimeRefIndexBox{buffer: [3, 5]}
    let v1  = box[1]
    let v0  = box[0]

    Swag.assert(v1 == 5)
    Swag.assert(v0 == 3)
    Swag.assert(box.reads == 2)
}

#test
{
    const box = RuntimeRefIndexBox{buffer: [11, 13]}
    let value = box[0]

    Swag.assert(value == 11)
}

#test
{
    var box   = RuntimeMultiIndexBox{values: [10, 20, 30, 40]}
    let value = box[1, 0]

    Swag.assert(value == 30)
    Swag.assert(box.reads == 1)
}

#test
{
    var holder = RuntimeIndexHolder{
        value: RuntimeValueIndexBox{first: 1, second: 2},
        refs: RuntimeRefIndexBox{buffer: [20, 30]}
        }

    let nested    = holder.value[1]
    let nestedRef = holder.refs[0]

    Swag.assert(nested == 2)
    Swag.assert(nestedRef == 20)
    Swag.assert(holder.value.reads == 1)
    Swag.assert(holder.refs.reads == 1)
}

enum RuntimeIndexedSlot { First, Second, Third }

enum RuntimeIndexedColumn { Left, Right }

enum ReorderedRuntimeIndexedSlot: u8
{
    Third  = 2
    First  = 0
    Second = 1
}

enum SingletonRuntimeIndexedSlot
{
    Only
}

#[Swag.Strict]
alias StrictRuntimeIndexedSlot = RuntimeIndexedSlot

enum RuntimeWideIndexedSlot
{
    Low  = 1
    Mid  = 84
    High = 120
}

struct RuntimeIndexedNativeState
{
    storage: [256] u8
}

struct RuntimeIndexedState
{
    using native: RuntimeIndexedNativeState
    values:       [RuntimeIndexedSlot] bool
}

struct RuntimeIndexedHolder
{
    state:      RuntimeIndexedState
    oldState:   RuntimeIndexedState
    wideValues: [128] bool
}

impl RuntimeIndexedHolder
{
    func readSlot(slot: RuntimeIndexedSlot)->bool
    {
        return false
    }

    mtd readSlot(slot: RuntimeIndexedSlot)->bool
    {
        return .state.values[slot]
    }

    func readWideSlot(slot: RuntimeWideIndexedSlot)->bool
    {
        return false
    }

    mtd readWideSlot(slot: RuntimeWideIndexedSlot)->bool
    {
        return .wideValues[cast(u64) slot]
    }
}

func readRuntimeIndexedSlot(holder: *RuntimeIndexedHolder, slot: RuntimeIndexedSlot)->bool
{
    return holder.state.values[slot]
}

func readStrictRuntimeIndexedSlot(values: [RuntimeIndexedSlot] bool, slot: StrictRuntimeIndexedSlot)->bool
{
    return values[slot]
}

func readRuntimeWideIndexedSlot(values: [128] bool, slot: RuntimeWideIndexedSlot)->bool
{
    return values[cast(u64) slot]
}

#test
{
    const values: [RuntimeIndexedSlot] s32 = [0, 1, 2]
    const first = values[RuntimeIndexedSlot.First]
    Swag.assert(first == 0)

    var index = RuntimeIndexedSlot.Third
    Swag.assert(values[index] == 2)
}

#test
{
    const reordered: [ReorderedRuntimeIndexedSlot] s32 = [10, 20, 30]
    #assert(#typeof(reordered) == [ReorderedRuntimeIndexedSlot] s32)
    Swag.assert(reordered[ReorderedRuntimeIndexedSlot.First] == 10)
    Swag.assert(reordered[ReorderedRuntimeIndexedSlot.Second] == 20)
    Swag.assert(reordered[ReorderedRuntimeIndexedSlot.Third] == 30)

    const singleton: [SingletonRuntimeIndexedSlot] s32 = [42]
    #assert(#typeof(singleton) == [SingletonRuntimeIndexedSlot] s32)
    Swag.assert(singleton[SingletonRuntimeIndexedSlot.Only] == 42)
}

#test
{
    var values: [RuntimeIndexedSlot] bool

    values[RuntimeIndexedSlot.Second] = true
    Swag.assert(values[RuntimeIndexedSlot.Second])
    Swag.assert(values[1])

    var index = RuntimeIndexedSlot.Second
    Swag.assert(values[index])
}

#test
{
    var values: [RuntimeIndexedSlot, RuntimeIndexedColumn] s32

    values[RuntimeIndexedSlot.Third, RuntimeIndexedColumn.Right] = 42
    Swag.assert(values[RuntimeIndexedSlot.Third, RuntimeIndexedColumn.Right] == 42)

    let row = values[RuntimeIndexedSlot.Third]
    #assert(#typeof(row) == [RuntimeIndexedColumn] s32)
    Swag.assert(row[RuntimeIndexedColumn.Right] == 42)
}

#test
{
    var values: [RuntimeIndexedSlot] bool

    values[cast(StrictRuntimeIndexedSlot) RuntimeIndexedSlot.Second] = true
    Swag.assert(values[cast(StrictRuntimeIndexedSlot) RuntimeIndexedSlot.Second])

    var index = cast(StrictRuntimeIndexedSlot) RuntimeIndexedSlot.Second
    Swag.assert(values[index])
    Swag.assert(readStrictRuntimeIndexedSlot(&values, index))
}

#test
{
    var holder: RuntimeIndexedHolder

    holder.state.values[RuntimeIndexedSlot.Second] = true
    Swag.assert(holder.state.values[RuntimeIndexedSlot.Second])

    var index = RuntimeIndexedSlot.Second
    Swag.assert(holder.state.values[index])
}

#test
{
    var holder: RuntimeIndexedHolder

    holder.state.values[RuntimeIndexedSlot.Second] = true
    Swag.assert(readRuntimeIndexedSlot(&holder, RuntimeIndexedSlot.Second))
    Swag.assert(holder.readSlot(RuntimeIndexedSlot.Second))

    var index = RuntimeIndexedSlot.Second
    Swag.assert(readRuntimeIndexedSlot(&holder, index))
    Swag.assert(holder.readSlot(index))
}

#test
{
    var values: [128] bool

    values[cast(u64) RuntimeWideIndexedSlot.Mid] = true
    Swag.assert(values[cast(u64) RuntimeWideIndexedSlot.Mid])
    Swag.assert(readRuntimeWideIndexedSlot(&values, RuntimeWideIndexedSlot.Mid))

    var index = RuntimeWideIndexedSlot.Mid
    Swag.assert(readRuntimeWideIndexedSlot(&values, index))
}

#test
{
    var holder: RuntimeIndexedHolder

    holder.wideValues[cast(u64) RuntimeWideIndexedSlot.Mid] = true
    Swag.assert(holder.wideValues[cast(u64) RuntimeWideIndexedSlot.Mid])
    Swag.assert(holder.readWideSlot(RuntimeWideIndexedSlot.Mid))

    var index = RuntimeWideIndexedSlot.Mid
    Swag.assert(holder.readWideSlot(index))
}

// An 'opIndex' call in a truthiness context is wrapped in an implicit cast, and code
// generation must keep resolving the wrapped node to that cast: losing the link left the
// enclosing 'if' with no condition to branch on.
#[Swag.NoInline]
func runtimeValueIndexIsNotEmpty(first: s32)->s32
{
    var box    = RuntimeValueIndexBox{first: first, second: 9}
    var result = 0's32
    if box[0] do
        result = 1
    return result
}

#test
{
    Swag.assert(runtimeValueIndexIsNotEmpty(7) == 1)
    Swag.assert(runtimeValueIndexIsNotEmpty(0) == 0)
}
