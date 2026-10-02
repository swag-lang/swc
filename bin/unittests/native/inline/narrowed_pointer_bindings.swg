#global private

// A nullable pointer that flow narrowing proved non-null can feed an inlined call, as a
// receiver or as an argument bound to a non-null pointer parameter. The binding is initialized
// once in the caller, where the proof holds, and the body works through the same object.

struct NarrowedCounter
{
    value: s32
}

struct NarrowedHolder
{
    counter: *NarrowedCounter?
}

impl NarrowedCounter
{
    #[Swag.Inline]
    mtd bump(step: s32)->s32
    {
        .value += step
        return .value
    }
}

#[Swag.Inline]
func narrowedAdd(counter: *NarrowedCounter, step: s32)->s32
{
    counter.value += step
    return counter.value
}

#[Swag.NoInline]
func narrowedFind(counters: [*] NarrowedCounter, count: s32, wanted: s32)->*NarrowedCounter?
{
    for i in count
    {
        if counters[i].value == wanted do
            return &counters[i]
    }

    return null
}

#[Swag.NoInline]
func narrowedReceiverAfterReturn(counters: [*] NarrowedCounter)->s32
{
    let counter = narrowedFind(counters, 3, 20)
    if not counter do
        return -1
    return counter.bump(5) + counter.bump(1)
}

#[Swag.NoInline]
func narrowedArgumentInBranch(counters: [*] NarrowedCounter, wanted: s32)->s32
{
    let counter = narrowedFind(counters, 3, wanted)
    if counter do
        return narrowedAdd(counter, 7)
    return -1
}

#[Swag.NoInline]
func narrowedMemberReceiver(holder: *NarrowedHolder)->s32
{
    if not holder.counter do
        return -1
    discard holder.counter.bump(2)
    return narrowedAdd(holder.counter, 3)
}

#test
{
    var counters: [3] NarrowedCounter
    counters[0].value = 10
    counters[1].value = 20
    counters[2].value = 30

    Swag.assert(narrowedReceiverAfterReturn(&counters[0]) == 51)
    Swag.assert(counters[1].value == 26)
    Swag.assert(narrowedReceiverAfterReturn(&counters[0]) == -1)

    Swag.assert(narrowedArgumentInBranch(&counters[0], 30) == 37)
    Swag.assert(counters[2].value == 37)
    Swag.assert(narrowedArgumentInBranch(&counters[0], 99) == -1)

    var holder = NarrowedHolder{counter: &counters[0]}
    Swag.assert(narrowedMemberReceiver(&holder) == 15)
    Swag.assert(counters[0].value == 15)

    var empty: NarrowedHolder
    Swag.assert(narrowedMemberReceiver(&empty) == -1)
}
