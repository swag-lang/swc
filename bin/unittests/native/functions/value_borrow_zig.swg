#global private

// Reduced from ziglang/zig#5973: a mutable parent aliases its by-value field.
// The wider field exercises Swag's indirect ABI; the small field uses a register.
struct Thing { value, padding1, padding2: u64 }
struct State { thing: Thing }

#[Swag.NoInline]
func inner(state: *State, thing: Thing)->u64
{
    let before = thing.value
    state.thing.value = 0
    return before + thing.value
}

struct SmallThing { value: u32 }
struct SmallState { thing: SmallThing }

#[Swag.NoInline]
func innerSmall(state: *SmallState, thing: SmallThing)->u32
{
    let before = thing.value
    state.thing.value = 0
    return before + thing.value
}

#test
{
    var state: State = State{thing: Thing{value: 10}}
    let observed     = inner(&state, #copy state.thing)
    Swag.assert(observed == 20)
    Swag.assert(state.thing.value == 0)

    var small: SmallState = SmallState{thing: SmallThing{value: 10}}
    let smallObserved     = innerSmall(&small, small.thing)
    Swag.assert(smallObserved == 20)
    Swag.assert(small.thing.value == 0)
}

var globalThing: Thing

#[Swag.NoInline]
func changeGlobal(thing: Thing)->u64
{
    globalThing.value = 1
    return thing.value
}

#test
{
    globalThing.value = 10
    let observed = changeGlobal(#copy globalThing)
    Swag.assert(observed == 10)
    Swag.assert(globalThing.value == 1)
}

var copyCount, dropCount, evaluationCount: u32

struct Counted { value, padding1, padding2: u64 }
impl Counted
{
    mtd opPostCopy() { copyCount += 1; .value += 1 }
    mtd opDrop() { dropCount += 1 }
}

#[Swag.NoInline]
func observe(value: Counted, original: const *Counted)->u64
{
    Swag.assert(&value != original)
    return value.value
}

#[Swag.NoInline]
func source(value: *Counted)->*Counted
{
    evaluationCount += 1
    return value
}

#test
{
    copyCount, dropCount, evaluationCount = 0
    var value: Counted = Counted{value: 10}
    let observed       = observe(#copy source(&value)[], &value)
    Swag.assert(observed == 11 and value.value == 10)
    Swag.assert(copyCount == 1 and evaluationCount == 1)
    Swag.assert(dropCount == 1)
}

// A copied element survives a growth that may release the previous allocation.
#[Swag.NoInline]
func appendWithGrowth(data: *[*] Thing, item: Thing)
{
    data[]    = expect cast([*] Thing, testRealloc(data[], 2 * #sizeof(Thing)))
    data[][1] = item
}

#test
{
    var data = expect cast([*] Thing, testAlloc(#sizeof(Thing)))
    defer testFree(data)
    data[0] = {value: 17}
    appendWithGrowth(&data, #copy data[0])
    Swag.assert(data[0].value == 17 and data[1].value == 17)
}

#[Swag.NoInline]
func replaceText(text: string, original: *string)->u64
{
    original[] = "changed"
    return text.count
}

#test
{
    var text     = "abc"
    let observed = replaceText(#copy text, &text)
    Swag.assert(observed == 3 and text == "changed")
}

#test
{
    copyCount, dropCount = 0
    var value: Counted = Counted{value: 20}
    scope
    {
        var snapshot = #copy value
        Swag.assert(snapshot.value == 21 and value.value == 20)
        Swag.assert(copyCount == 1 and dropCount == 0)
        snapshot.value = 23
        Swag.assert(value.value == 20)
    }
    Swag.assert(dropCount == 1)
}

#[Swag.NoInline]
func observeArray(values: [2] Counted, original: const *[2] Counted)->u64
{
    Swag.assert(&values != original)
    return values[0].value + values[1].value
}

#test
{
    copyCount, dropCount = 0
    var values: [2] Counted = [Counted{value: 3}, Counted{value: 5}]
    let observed = observeArray(#copy values, &values)
    Swag.assert(observed == 10)
    Swag.assert(copyCount == 2 and dropCount == 2)
    Swag.assert(values[0].value == 3 and values[1].value == 5)
}

#[Swag.NoInline]
func observeSelected(selectFirst: bool, first, second: *Counted)->u64
{
    return observe(selectFirst ? #copy first[] : #copy second[], selectFirst ? first : second)
}

#test
{
    copyCount, dropCount = 0
    var first:  Counted = Counted{value: 3}
    var second: Counted = Counted{value: 5}
    let observed        = observeSelected(false, &first, &second)
    Swag.assert(observed == 6)
    Swag.assert(copyCount == 1)
    Swag.assert(dropCount == 1)
    let firstObserved = observeSelected(true, &first, &second)
    Swag.assert(firstObserved == 4 and copyCount == 2 and dropCount == 2)
}

#[Swag.NoInline]
func returnCopy(value: const *Counted)->Counted => #copy value[]

#[Swag.Inline]
func observeInlineCopy(value: const *Counted)->u64
{
    return observe(#copy value[], value)
}

#test
{
    copyCount, dropCount = 0
    var value: Counted = Counted{value: 12}
    scope
    {
        let snapshot = returnCopy(&value)
        Swag.assert(snapshot.value == 13 and copyCount == 1 and dropCount == 0)
    }
    Swag.assert(dropCount == 1)
    let observed = observeInlineCopy(&value)
    Swag.assert(observed == 13 and copyCount == 2 and dropCount == 2)
}

func makeCopiedThing()->Thing => #copy Thing{value: 31}

var initializedCopy: Thing = #run makeCopiedThing()

#test
{
    Swag.assert(initializedCopy.value == 31)
}

#[Swag.NoInline]
func observeBeforeDeferredCleanup(value: const *Counted)->u64
{
    defer Swag.assert(dropCount == 1)
    return observe(#copy value[], value)
}

#test
{
    copyCount, dropCount = 0
    var value: Counted = Counted{value: 9}
    let observed       = observeBeforeDeferredCleanup(&value)
    Swag.assert(observed == 10 and dropCount == 1)
}

#[Swag.NoInline]
func mutateBoxBesideValue(value: Thing, boxed: any)->u64
{
    let target = assume cast(*u64, boxed)
    target[] = 37
    return value.value
}

#test
{
    var value: Thing = Thing{value: 19}
    let observed     = mutateBoxBesideValue(value, #copy value.value)
    Swag.assert(observed == 19 and value.value == 19)
}

struct NestedCounted
{
    field: Counted
    tag:   u64
}

impl NestedCounted
{
    mtd opPostCopy() { .tag += 1 }
}

#[Swag.NoInline]
func observeNested(value: NestedCounted)->u64
{
    globalThing.value = 0
    return value.field.value + value.tag
}

#test
{
    copyCount, dropCount = 0
    var value: NestedCounted = NestedCounted{field: Counted{value: 10}, tag: 20}
    Swag.assert(observeNested(#copy value) == 32)
    Swag.assert(value.field.value == 10 and value.tag == 20)
    Swag.assert(copyCount == 1 and dropCount == 1)
}

func makeNestedSnapshot()->u64
{
    var value: NestedCounted = NestedCounted{field: Counted{value: 10}, tag: 20}
    return observeNested(#copy value)
}

const NESTED_SNAPSHOT = #run makeNestedSnapshot()
#assert(NESTED_SNAPSHOT == 32)
