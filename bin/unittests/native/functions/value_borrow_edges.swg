#global private

// Runtime versions of the constructor, publication, and callback cases from the static experiment.
struct Value { first, second, third: u64 }
func mustReject(action: func||())
{
    let caught = Swag.catchPanic(action)
    Swag.assert(caught.raised)
    Swag.assert(caught.message() == "write overlaps storage borrowed by a value argument")
}

struct SelfValue { value, padding: u64; target: *SelfValue? }
impl SelfValue
{
    #[Swag.Implicit]
    mtd opSet(value: u64) { .value = value; .target = me }
}
#[Swag.NoInline]
func writeConstructed(value: SelfValue)->u64
{
    value.target!.value = 0
    return value.value
}
#test
{
    mustReject(func() { discard writeConstructed(179'u64) })
}

var globalValue: Value
struct MovedValue { first, second, third: u64 }
impl MovedValue
{
    mtd opPostMove() { globalValue.first = 0 }
}
#[Swag.NoInline]
func readSelection(value: Value, selected: MovedValue)->u64 => value.first + selected.first
#test
{
    for selectFirst in [true, false]
    {
        globalValue.first = 181
        var first, second: MovedValue
        mustReject(func|selectFirst, &first, &second|() {
            discard readSelection(globalValue, selectFirst ? #copy first : #copy second)
        })
        Swag.assert(globalValue.first == 181)
    }
}

alias Writer = func(Value, *Value)->u64
#[Swag.NoInline]
func write(value: Value, target: *Value)->u64
{
    target.first = 0
    return value.first
}
#test
{
    var value: Value = {first: 191}
    let encoded      = cast(u64, cast(*void, &write))
    let callback     = cast(Writer, cast(*void, encoded))
    mustReject(func|callback, &value|() { discard callback(value, &value) })
    Swag.assert(value.first == 191)
    let observed = callback(#copy value, &value)
    Swag.assert(observed == 191 and value.first == 0)
}

var published: u64
#[Swag.NoInline]
func publish(address: u64) { discard Swag.atomxchg(&published, address) }
struct PublishedValue { first, second, third: u64 }
impl PublishedValue
{
    #[Swag.Implicit]
    mtd opSet(value: u64) { .first = value; publish(cast(u64, me)) }
    mtd opPostCopy() { publish(cast(u64, me)) }
}
#[Swag.NoInline]
func mutatePublished(value: PublishedValue, target: *PublishedValue)->u64
{
    target.first = 0
    return value.first
}
#test
{
    var value: PublishedValue = {first: 193}
    mustReject(func|&value|() {
        discard mutatePublished(#copy value, cast(*PublishedValue, published))
    })
    Swag.assert(value.first == 193)
    published = 0
}

#[Swag.NoInline]
func replaceString(value: string, target: *string)->u64
{
    target[] = "replacement"
    return value.count
}
#[Swag.NoInline]
func replaceSlice(value: [..] u64, target: *[..] u64, replacement: [..] u64)->u64
{
    target[] = replacement
    return value.count
}
#test
{
    var text = "original"
    mustReject(func|&text|() { discard replaceString(text, &text) })
    Swag.assert(text == "original")
    let length = replaceString(#copy text, &text)
    Swag.assert(length == 8 and text == "replacement")

    var first          = [1'u64, 2]
    var second         = [3'u64, 4, 5]
    var view: [..] u64 = first
    mustReject(func|&view, &second|() { discard replaceSlice(view, &view, second) })
    Swag.assert(view.count == 2)
    let count = replaceSlice(#copy view, &view, second)
    Swag.assert(count == 2 and view.count == 3)
}

struct BorrowError {}
#[Swag.NoInline]
func failWhileBorrowing(value: Value, observed: *u64) fail
{
    defer observed[] = value.first
    fail BorrowError{}
}
#[Swag.NoInline]
func failLater()->u64 fail { fail BorrowError{} }
#[Swag.NoInline]
func readLater(value: Value, later: u64)->u64 => value.first + later
#[Swag.NoInline]
func readFailingLater(value: Value)->u64 fail => readLater(value, try failLater())
#test
{
    var value:    Value = {first: 197}
    var observed: u64
    catch failWhileBorrowing(value, &observed)
    Swag.assert(observed == 197)
    value.first = 199
    discard catch readFailingLater(value)
    value.first = 211
    Swag.assert(value.first == 211)
}

#[Swag.NoInline]
func writeInDefer(value: Value, target: *Value)->u64
{
    defer target.first = 0
    return value.first
}
#test
{
    var value: Value = {first: 223}
    mustReject(func|&value|() { discard writeInDefer(value, &value) })
    Swag.assert(value.first == 223)
    let observed = writeInDefer(#copy value, &value)
    Swag.assert(observed == 223 and value.first == 0)
}

#[Swag.NoInline]
func writeByte(value: Value, target: [*] u8, offset: u64, count: u64)->u64
{
    Swag.memset(target + offset, 0, count)
    return value.first
}
#test
{
    var values: [3] Value
    values[1].first = 227
    let bytes = cast([*] u8, &values)
    let width = #sizeof(Value)
    // Empty and adjacent ranges are valid; crossing either boundary by one byte is not.
    let empty  = writeByte(values[1], bytes, width, 0)
    let before = writeByte(values[1], bytes, width - 1, 1)
    let after  = writeByte(values[1], bytes, width * 2, 1)
    Swag.assert(empty == 227 and before == 227 and after == 227)
    mustReject(func|&values, bytes, width|() { discard writeByte(values[1], bytes, width - 1, 2) })
    mustReject(func|&values, bytes, width|() { discard writeByte(values[1], bytes, width * 2 - 1, 2) })
    Swag.assert(values[1].first == 227)
}

// The caller must protect an earlier argument before evaluating the next one,
// including calls emitted directly inside a test or compiler-run entry point.
#[Swag.NoInline]
func probeEarlierArgument(target: *Value, borrowed: bool)->u64
{
    let caught = Swag.catchPanic(func|target|() { target.first = 0 })
    Swag.assert(caught.raised == borrowed)
    if borrowed do
        Swag.assert(caught.message() == "write overlaps storage borrowed by a value argument")
    return 1
}
#[Swag.NoInline]
func sumEarlierArgument(value: Value, other: u64)->u64 => value.first + other
#[Swag.Inline]
func inlineEarlierArgument(value: Value, other: u64)->u64 => value.first + other
#test
{
    var value: Value = {first: 229}
    let ordinary     = sumEarlierArgument(value, probeEarlierArgument(&value, true))
    Swag.assert(ordinary == 230 and value.first == 229)
    let copied = sumEarlierArgument(#copy value, probeEarlierArgument(&value, false))
    Swag.assert(copied == 230 and value.first == 0)
}
#test
{
    var value: Value = {first: 233}
    let inlined      = inlineEarlierArgument(value, probeEarlierArgument(&value, true))
    Swag.assert(inlined == 234 and value.first == 233)
    let copied = inlineEarlierArgument(#copy value, probeEarlierArgument(&value, false))
    Swag.assert(copied == 234 and value.first == 0)
}

#test
{
    const computed = #run sumEarlierArgument(Value{241, 0, 0}, 1)
    Swag.assert(computed == 242)
}

#[Swag.NoInline]
func floatArgument(value: Value)->f64 => cast(f64, value.first) + 0.5
#test
{
    const computed = #run floatArgument(Value{251, 0, 0})
    Swag.assert(computed == 251.5)
    const blockComputed = #run { return sumEarlierArgument(Value{257, 0, 0}, 1) }
    Swag.assert(blockComputed == 258)
}

#[Swag.Inline]
func replaceAny(value: any, target: *any)->s32
{
    target[] = 0's32
    return assume cast(s32, value)
}
#test
{
    var value: any = 283's32
    mustReject(func|&value|() { discard replaceAny(value, &value) })
    let observed = replaceAny(#copy value, &value)
    Swag.assert(observed == 283 and assume cast(s32, value) == 0)
}

#[Swag.NoInline]
func readBesidePublished(value: PublishedValue, other: u64)->u64 => value.first + other
#[Swag.NoInline]
func writePublished()->u64
{
    cast(*PublishedValue, published).first = 0
    return 1
}
#test
{
    var value: PublishedValue = {first: 293}
    mustReject(func|&value|() { discard readBesidePublished(#copy value, writePublished()) })
    Swag.assert(value.first == 293)
    published = 0
}

#[Swag.NoInline]
func readAcrossTask(value: Value, target: *Value)->u64
{
    var caught = false
    var group: Swag.TaskGroup
    group.spawn(func|target, &caught|() {
        let panic = Swag.catchPanic(func|target|() { target.first = 0 })
        caught = panic.raised and panic.message() == "write overlaps storage borrowed by a value argument"
    })
    expect group.join()
    Swag.assert(caught)
    return value.first
}

// Joining orders the accesses; the guard observes an existing borrow across task contexts.
#test
{
    var value: Value = {first: 307}
    let observed     = readAcrossTask(value, &value)
    Swag.assert(observed == 307 and value.first == 307)
    value.first = 311
    Swag.assert(value.first == 311)
}

var defaultValue: Value
#[Swag.NoInline]
func readDefault(value: Value, extra: u64 = 1)->u64
{
    defaultValue.first = 0
    return value.first + extra
}
#[Swag.Inline]
func readInlineDefault(value: Value, extra: u64 = 1)->u64
{
    defaultValue.first = 0
    return value.first + extra
}
#test
{
    defaultValue.first = 313
    mustReject(func() { discard readDefault(defaultValue) })
    Swag.assert(defaultValue.first == 313)
    mustReject(func() { discard readInlineDefault(defaultValue) })
    Swag.assert(defaultValue.first == 313)
    let observed = readDefault(#copy defaultValue)
    Swag.assert(observed == 314 and defaultValue.first == 0)
}

#[Swag.NoInline]
func makePublished()->PublishedValue
{
    var result: retval
    result.first = 331
    publish(cast(u64, &result))
    return result
}
#[Swag.Inline]
func makeInlinePublished()->PublishedValue
{
    var result: retval
    result.first = 337
    publish(cast(u64, &result))
    return result
}

// Publication from construction and return storage must be protected before the next argument.
#test
{
    mustReject(func() { discard readBesidePublished(makePublished(), writePublished()) })
    published = 0
    mustReject(func() { discard readBesidePublished(makeInlinePublished(), writePublished()) })
    published = 0
    mustReject(func() { discard readBesidePublished(347'u64, writePublished()) })
    published = 0
}
