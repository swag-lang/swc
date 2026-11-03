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

    Swag.require(a == 7)
    Swag.require(b == 9)
    Swag.require(box.reads == 2)
}

#test
{
    var box = RuntimeRefIndexBox{buffer: [3, 5]}
    let v1  = box[1]
    let v0  = box[0]

    Swag.require(v1 == 5)
    Swag.require(v0 == 3)
    Swag.require(box.reads == 2)
}

#test
{
    const box = RuntimeRefIndexBox{buffer: [11, 13]}
    let value = box[0]

    Swag.require(value == 11)
}

#test
{
    var box   = RuntimeMultiIndexBox{values: [10, 20, 30, 40]}
    let value = box[1, 0]

    Swag.require(value == 30)
    Swag.require(box.reads == 1)
}

#test
{
    var holder = RuntimeIndexHolder{
        value: RuntimeValueIndexBox{first: 1, second: 2},
        refs: RuntimeRefIndexBox{buffer: [20, 30]}
        }

    let nested    = holder.value[1]
    let nestedRef = holder.refs[0]

    Swag.require(nested == 2)
    Swag.require(nestedRef == 20)
    Swag.require(holder.value.reads == 1)
    Swag.require(holder.refs.reads == 1)
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
    func readSlot(_: RuntimeIndexedSlot)->bool
    {
        return false
    }

    mtd readSlot(slot: RuntimeIndexedSlot)->bool
    {
        return .state.values[slot]
    }

    func readWideSlot(_: RuntimeWideIndexedSlot)->bool
    {
        return false
    }

    mtd readWideSlot(slot: RuntimeWideIndexedSlot)->bool
    {
        return .wideValues[cast(u64, slot)]
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
    return values[cast(u64, slot)]
}

#test
{
    const values: [RuntimeIndexedSlot] s32 = [0, 1, 2]
    const first = values[RuntimeIndexedSlot.First]
    Swag.require(first == 0)

    var index = RuntimeIndexedSlot.Third
    Swag.require(values[index] == 2)
}

#test
{
    const reordered: [ReorderedRuntimeIndexedSlot] s32 = [10, 20, 30]
    #assert(#typeof(reordered) == [ReorderedRuntimeIndexedSlot] s32)
    Swag.require(reordered[ReorderedRuntimeIndexedSlot.First] == 10)
    Swag.require(reordered[ReorderedRuntimeIndexedSlot.Second] == 20)
    Swag.require(reordered[ReorderedRuntimeIndexedSlot.Third] == 30)

    const singleton: [SingletonRuntimeIndexedSlot] s32 = [42]
    #assert(#typeof(singleton) == [SingletonRuntimeIndexedSlot] s32)
    Swag.require(singleton[SingletonRuntimeIndexedSlot.Only] == 42)
}

#test
{
    var values: [RuntimeIndexedSlot] bool

    values[RuntimeIndexedSlot.Second] = true
    Swag.require(values[RuntimeIndexedSlot.Second])
    Swag.require(values[1])

    var index = RuntimeIndexedSlot.Second
    Swag.require(values[index])
}

#test
{
    var values: [RuntimeIndexedSlot, RuntimeIndexedColumn] s32

    values[RuntimeIndexedSlot.Third, RuntimeIndexedColumn.Right] = 42
    Swag.require(values[RuntimeIndexedSlot.Third, RuntimeIndexedColumn.Right] == 42)

    let row = values[RuntimeIndexedSlot.Third]
    #assert(#typeof(row) == [RuntimeIndexedColumn] s32)
    Swag.require(row[RuntimeIndexedColumn.Right] == 42)
}

#test
{
    var values: [RuntimeIndexedSlot] bool

    values[cast(StrictRuntimeIndexedSlot, RuntimeIndexedSlot.Second)] = true
    Swag.require(values[cast(StrictRuntimeIndexedSlot, RuntimeIndexedSlot.Second)])

    var index = cast(StrictRuntimeIndexedSlot, RuntimeIndexedSlot.Second)
    Swag.require(values[index])
    Swag.require(readStrictRuntimeIndexedSlot(&values, index))
}

#test
{
    var holder: RuntimeIndexedHolder

    holder.state.values[RuntimeIndexedSlot.Second] = true
    Swag.require(holder.state.values[RuntimeIndexedSlot.Second])

    var index = RuntimeIndexedSlot.Second
    Swag.require(holder.state.values[index])
}

#test
{
    var holder: RuntimeIndexedHolder

    holder.state.values[RuntimeIndexedSlot.Second] = true
    Swag.require(readRuntimeIndexedSlot(&holder, RuntimeIndexedSlot.Second))
    Swag.require(holder.readSlot(RuntimeIndexedSlot.Second))

    var index = RuntimeIndexedSlot.Second
    Swag.require(readRuntimeIndexedSlot(&holder, index))
    Swag.require(holder.readSlot(index))
}

#test
{
    var values: [128] bool

    values[cast(u64, RuntimeWideIndexedSlot.Mid)] = true
    Swag.require(values[cast(u64, RuntimeWideIndexedSlot.Mid)])
    Swag.require(readRuntimeWideIndexedSlot(&values, RuntimeWideIndexedSlot.Mid))

    var index = RuntimeWideIndexedSlot.Mid
    Swag.require(readRuntimeWideIndexedSlot(&values, index))
}

#test
{
    var holder: RuntimeIndexedHolder

    holder.wideValues[cast(u64, RuntimeWideIndexedSlot.Mid)] = true
    Swag.require(holder.wideValues[cast(u64, RuntimeWideIndexedSlot.Mid)])
    Swag.require(holder.readWideSlot(RuntimeWideIndexedSlot.Mid))

    var index = RuntimeWideIndexedSlot.Mid
    Swag.require(holder.readWideSlot(index))
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
    Swag.require(runtimeValueIndexIsNotEmpty(7) == 1)
    Swag.require(runtimeValueIndexIsNotEmpty(0) == 0)
}
