#global private
#global #[Swag.Safety(.ValueBorrow, true)]

// Dynamic counterparts of ziglang/zig#5973 and the previous static borrow regressions.
struct Thing { value, padding1, padding2: u64 }
struct State { thing: Thing; other: Thing }

func mustReject(action: func||())
{
    let caught = Swag.catchPanic(action)
    Swag.assert(caught.raised)
    Swag.assert(caught.message() == "write overlaps storage borrowed by a value argument")
}

#[Swag.NoInline]
func inner(state: *State, thing: Thing)->u64
{
    state.thing.value = 0
    return thing.value
}

// Zig's mutable parent aliases its by-value field. The store must not run.
#test
{
    var state: State = {thing: {value: 10}}
    mustReject(func|&state|() { discard inner(&state, state.thing) })
    Swag.assert(state.thing.value == 10)
    Swag.assert(inner(&state, #copy state.thing) == 10)
    Swag.assert(state.thing.value == 0)
}

var globalThing: Thing
#[Swag.NoInline]
func changeGlobal(thing: Thing)->u64
{
    globalThing.value = 0
    return thing.value
}

#test
{
    globalThing.value = 19
    mustReject(func() { discard changeGlobal(globalThing) })
    Swag.assert(globalThing.value == 19)
    Swag.assert(changeGlobal(#copy globalThing) == 19)
}

#[Swag.NoInline]
func restoreAfterWrite(thing: Thing, destination: *Thing)->u64
{
    let before = destination.value
    destination.value = 0
    destination.value = before
    return thing.value
}

// An entry/exit checksum would miss this transient mutation.
#test
{
    var thing: Thing = {value: 23}
    mustReject(func|&thing|() { discard restoreAfterWrite(thing, &thing) })
    Swag.assert(thing.value == 23)
}

struct SelfReferential { value, padding: u64; target: *SelfReferential? }
#[Swag.NoInline]
func mutateSelf(value: SelfReferential)->u64
{
    value.target!.value = 0
    return value.value
}

#test
{
    var value: SelfReferential = {value: 29}
    value.target = &value
    mustReject(func|&value|() { discard mutateSelf(value) })
    Swag.assert(value.value == 29)
    // A shallow copy points back to the original, which is now outside the borrow.
    Swag.assert(mutateSelf(#copy value) == 29)
    Swag.assert(value.value == 0)
}

#[Swag.NoInline]
func throughCallback(value: Thing, callback: func||())->u64
{
    callback()
    return value.value
}

#test
{
    var value: Thing = {value: 31}
    mustReject(func|&value|() {
        discard throughCallback(value, func|&value|() { value.value = 0 })
    })
    Swag.assert(value.value == 31)
    var other: Thing
    Swag.assert(throughCallback(value, func|&other|() { other.value = 37 }) == 31)
    Swag.assert(other.value == 37)
}

#[Swag.Inline]
func inlineMutation(value: Thing, destination: *Thing)->u64
{
    destination.value = 0
    return value.value
}

#test
{
    var value: Thing = {value: 41}
    mustReject(func|&value|() { discard inlineMutation(value, &value) })
    Swag.assert(value.value == 41)
    Swag.assert(inlineMutation(#copy value, &value) == 41)
}

#[Swag.NoInline]
func erasedMutation(value: Thing, address: u64)->u64
{
    cast(*u64, address)[] = 0
    return value.value
}

#test
{
    var value: Thing = {value: 43}
    mustReject(func|&value|() { discard erasedMutation(value, cast(u64, &value.value)) })
    Swag.assert(value.value == 43)
}

#[Swag.NoInline]
func byteMutation(value: Thing, destination: *void, operation: u32)->u64
{
    var source: Thing
    switch operation
    {
    case 0: Swag.memset(destination, 0, #sizeof(Thing))
    case 1: Swag.memcpy(destination, &source, #sizeof(Thing))
    case 2: Swag.memmove(destination, &source, #sizeof(Thing))
    case 3: discard Swag.atomicExchange(cast(*u64, destination), 0)
    case 4: Swag.atomicStore(cast(*u64, destination), 0)
    }
    return value.value
}

#test
{
    for operation in 5'u32
    {
        var value: Thing = {value: 47}
        mustReject(func|&value, operation|() { discard byteMutation(value, &value, operation) })
        Swag.assert(value.value == 47)
        var other: Thing
        Swag.assert(byteMutation(value, &other, operation) == 47)
    }
}

#[Swag.NoInline]
func laterArgument(destination: *Thing)->u64
{
    destination.value = 0
    return 1
}
#[Swag.NoInline]
func readBeside(value: Thing, other: u64)->u64 => value.value + other

// The borrow starts before a later argument executes.
#test
{
    var value: Thing = {value: 53}
    mustReject(func|&value|() { discard readBeside(value, laterArgument(&value)) })
    Swag.assert(value.value == 53)
    Swag.assert(readBeside(#copy value, laterArgument(&value)) == 54)
}

// Disjoint fields of one parent are not overlapping storage.
#test
{
    var state: State = {thing: {value: 59}, other: {value: 61}}
    Swag.assert(inner(&state, state.other) == 61)
    state.other.value = 67
    Swag.assert(state.thing.value == 0 and state.other.value == 67)
}

#[Swag.NoInline]
func nestedCatch(value: Thing, destination: *Thing)->u64
{
    let innerPanic = Swag.catchPanic(func() { Swag.panic("inner", #curlocation) })
    Swag.assert(innerPanic.raised)
    destination.value = 0
    return value.value
}

// Catching an inner panic must preserve the outer call's live borrow.
#test
{
    var value: Thing = {value: 71}
    mustReject(func|&value|() { discard nestedCatch(value, &value) })
    Swag.assert(value.value == 71)
    value.value = 73
    Swag.assert(value.value == 73)
}

// Repeated nonlocal exits must leave neither stale stack records nor a held registry lock.
#test
{
    for 32
    {
        var value: Thing = {value: 79}
        mustReject(func|&value|() { discard restoreAfterWrite(value, &value) })
        value.value = 83
        Swag.assert(value.value == 83)
    }
}

struct PublishedCopy { first, second, third: u64 }
var publishedCopy: *PublishedCopy?
impl PublishedCopy
{
    mtd opPostCopy() { publishedCopy = me }
}
#[Swag.NoInline]
func mutatePublished(value: PublishedCopy)->u64
{
    publishedCopy!.first = 0
    return value.first
}

// A copy is independent storage, but its hook can publish a new alias to that storage.
#test
{
    var value: PublishedCopy = {first: 89}
    mustReject(func|&value|() { discard mutatePublished(#copy value) })
    Swag.assert(value.first == 89)
    publishedCopy = null
}

struct NestedPublished { field: PublishedCopy }
impl NestedPublished
{
    mtd opPostCopy() { .field.second += 1 }
}
#[Swag.NoInline]
func mutatePublishedField(value: NestedPublished)->u64
{
    publishedCopy!.first = 0
    return value.field.first
}
#test
{
    var value: NestedPublished = {field: {first: 97}}
    mustReject(func|&value|() { discard mutatePublishedField(#copy value) })
    Swag.assert(value.field.first == 97)
    publishedCopy = null
}

struct SideEffectCopy { value: u64 }
impl SideEffectCopy
{
    mtd opPostCopy() { globalThing.value = 0 }
}
#[Swag.NoInline]
func readBesideCopy(value: Thing, other: SideEffectCopy)->u64 => value.value + other.value
struct NestedCopy { field: SideEffectCopy }
#[Swag.NoInline]
func readBesideNestedCopy(value: Thing, other: NestedCopy)->u64 => value.value + other.field.value

#test
{
    globalThing.value = 101
    var other: SideEffectCopy
    mustReject(func|&other|() { discard readBesideCopy(globalThing, #copy other) })
    Swag.assert(globalThing.value == 101)
    var nested: NestedCopy
    mustReject(func|&nested|() { discard readBesideNestedCopy(globalThing, #copy nested) })
    Swag.assert(globalThing.value == 101)
}

struct Carrier { target: *Thing }
#[Swag.NoInline]
func writeCarrier(value: Thing, carrier: Carrier)->u64
{
    let target = carrier.target
    target.value = 0
    return value.value
}
#test
{
    var value:   Thing   = {value: 103}
    let carrier: Carrier = {target: &value}
    mustReject(func|&value, carrier|() { discard writeCarrier(value, #copy carrier) })
    Swag.assert(value.value == 103)
}

#[Swag.NoInline]
func mutateBox(value: Thing, boxed: any)->u64
{
    let target = assume cast(*u64, boxed)
    target[] = 0
    return value.value
}
#test
{
    var value: Thing = {value: 107}
    mustReject(func|&value|() { discard mutateBox(value, value.value) })
    Swag.assert(value.value == 107)
    let observed = mutateBox(value, #copy value.value)
    Swag.assert(observed == 107 and value.value == 107)
}

#[Swag.NoInline]
func lifecycleMutation(value: Thing, target: *Thing, operation: u32)->u64
{
    switch operation
    {
    case 0: Swag.init(target)
    case 1: Swag.init(target)(Thing{value: 0})
    case 2: Swag.drop(target)
    }
    return value.value
}
#test
{
    for operation in 3'u32
    {
        var value: Thing = {value: 109}
        mustReject(func|&value, operation|() { discard lifecycleMutation(value, &value, operation) })
        Swag.assert(value.value == 109)
    }
}

#[Swag.NoInline]
func growInPlace(value: Thing, request: *Swag.AllocatorRequest)->u64
{
    let allocator = Swag.getContext().allocator!
    allocator.realloc(request)
    return value.value
}

// Capacity growth that keeps the borrowed bytes alive is valid and needs no copy.
#test
{
    let allocator = Swag.getContext().allocator!
    var request: Swag.AllocatorRequest
    request.size = #sizeof(Thing)
    allocator.alloc(&request)
    let address = request.address!
    defer allocator.free(&request)
    let value = cast(*Thing, address)
    Swag.init(value)
    value.value = 127
    // The host allocator exposes no spare capacity in padded JIT builds.
    // Native allocation rounds this block up, so its growth stays in place.
    request.size = Swag.jit() ? #sizeof(Thing) : 32
    let observed = growInPlace(value[], &request)
    Swag.assert(observed == 127 and request.address == address)
}

// The call-site borrow must survive lowering inside an assertion condition.
#test
{
    var value: Thing = {value: 131}
    mustReject(func|&value|() { Swag.assert(readBeside(value, laterArgument(&value)) == 132) })
    Swag.assert(value.value == 131)
}

#[Swag.Inline]
func inlineReadBeside(value: Thing, other: u64)->u64 => value.value + other
#test
{
    var value: Thing = {value: 137}
    mustReject(func|&value|() { discard inlineReadBeside(value, laterArgument(&value)) })
    Swag.assert(value.value == 137)
}

#[Swag.Safety(.ValueBorrow, false), Swag.NoInline]
func locallyCheckedWrite(target: *Thing)
{
    #[Swag.Safety(.ValueBorrow, true)]
    target.value = 0
}
#[Swag.NoInline]
func useLocallyCheckedWrite(value: Thing, target: *Thing)->u64
{
    locallyCheckedWrite(target)
    return value.value
}
#test
{
    var value: Thing = {value: 139}
    mustReject(func|&value|() { discard useLocallyCheckedWrite(value, &value) })
    Swag.assert(value.value == 139)
}

#[Swag.NoInline]
func exchangeIfEqual(value: Thing, target: *Thing, expected: u64)->u64
{
    discard Swag.atomicCompareExchange(&target.value, expected, 0)
    return value.value
}
#test
{
    var value: Thing = {value: 149}
    let observed     = exchangeIfEqual(value, &value, 0)
    Swag.assert(observed == 149 and value.value == 149)
    mustReject(func|&value|() { discard exchangeIfEqual(value, &value, 149) })
    Swag.assert(value.value == 149)
}

#[Swag.NoInline]
func destructure(value: Thing, target: *Thing)->u64
{
    {target.value, target.padding1} = {0'u64, 0'u64}
    return value.value
}
#test
{
    var value: Thing = {value: 151}
    mustReject(func|&value|() { discard destructure(value, &value) })
    Swag.assert(value.value == 151)
}

#[Swag.NoInline]
func moveFrom(value: Thing, target: *Thing)->u64
{
    let moved = #move target[]
    return value.value + moved.value
}
#test
{
    var value: Thing = {value: 157}
    mustReject(func|&value|() { discard moveFrom(value, &value) })
    Swag.assert(value.value == 157)
}

#[Swag.NoInline]
func variadicMutation(target: *Thing, values: ...)->u64
{
    target.value = 0
    return (assume cast(Thing, values[0])).value
}
#test
{
    var value: Thing = {value: 163}
    mustReject(func|&value|() { discard variadicMutation(&value, value) })
    Swag.assert(value.value == 163)
    let observed = variadicMutation(&value, #copy value)
    Swag.assert(observed == 163 and value.value == 0)
}

#[Swag.NoInline]
func initializeRange(value: Thing, target: [*] Thing, count: u64)->u64
{
    Swag.init(target, count)
    return value.value
}
#test
{
    var values: [3] Thing
    values[1].value = 167
    let unchanged = initializeRange(values[1], &values[0], 0)
    Swag.assert(unchanged == 167)
    mustReject(func|&values|() { discard initializeRange(values[1], &values[0], 3) })
    // Multiplying this count by sizeof(Thing) wraps to zero without a guarded extent.
    mustReject(func|&values|() { discard initializeRange(values[1], &values[0], 1'u64 << 61) })
    Swag.assert(values[1].value == 167)
}

struct IndexedReader { bias: u64 }
impl IndexedReader
{
    #[Swag.NoInline]
    mtd const opIndex(value: Thing, extra: Thing)->u64 => .bias + value.value + extra.value
}

#[Swag.NoInline]
func laterThing(destination: *Thing)->Thing
{
    destination.value = 0
    return {value: 1}
}

// An implicit operator call has the same argument-evaluation boundary as a named call.
#test
{
    var value:  Thing         = {value: 173}
    let reader: IndexedReader = {bias: 2}
    mustReject(func|&value, reader|() { discard reader[value, laterThing(&value)] })
    Swag.assert(value.value == 173)
    let observed = reader[#copy value, laterThing(&value)]
    Swag.assert(observed == 176 and value.value == 0)
}
