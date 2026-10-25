#global private

struct Value
{
    a, b, c: u64
}

#[Swag.NoInline]
func read(value: Value)->u64
{
    return value.a + value.b + value.c
}

#[Swag.NoInline]
func readAlias(value: Value, target: const *Value)->u64
{
    return value.a + target.a
}

#[Swag.NoInline]
func readMutableAlias(value: Value, target: *Value)->u64
{
    return value.a + target.a
}

#[Swag.NoInline]
func writeOther(value: Value, other: *u64)->u64
{
    other[] = 12
    return value.a
}

func accepted()->u64
{
    var value: Value = Value{a: 1, b: 2, c: 3}
    var other: u64
    let first        = read(value)
    let second       = readAlias(value, &value)
    let third        = readMutableAlias(value, &value)
    let fourth       = writeOther(value, &other)
    return first + second + third + fourth + other
}

#[Swag.CallingConvention(.C), Swag.NoInline]
func cValue(value: Value, target: *Value)->u64
{
    target.a = 13
    return value.a
}

func cCopy()->u64
{
    var value: Value = Value{a: 1, b: 2, c: 3}
    return cValue(value, &value)
}

#[Swag.NoInline]
func sameStorage(value: Value, expected: const *Value)->bool
{
    return &value == expected
}

func zeroCopy()->bool
{
    var value: Value = Value{a: 1, b: 2, c: 3}
    return sameStorage(value, &value)
}

#test
{
    Swag.assert(accepted() == 23)
    Swag.assert(cCopy() == 1)
    Swag.assert(zeroCopy())
}

#[Swag.NoCopy]
struct Unique
{
    a, b, c: u64
}

#[Swag.NoInline]
func readUnique(value: Unique, expected: const *Unique)->bool
{
    return &value == expected and value.a == 42
}

struct Small
{
    value: u32
}

#[Swag.NoInline]
func registerValue(value: Small, target: *Small)->u32
{
    target.value = 9
    return value.value
}

struct Odd
{
    a, b, c: u8
}

#[Swag.CallingConvention(.C), Swag.NoInline]
func cOdd(value: Odd, target: *Odd)->u8
{
    target.a = 9
    return value.a
}

#[Swag.Inline]
func inlineRead(value: Value)->u64 => value.a

#test
{
    var unique: Unique = Unique{a: 42}
    Swag.assert(readUnique(unique, &unique))
    var small: Small = Small{value: 3}
    Swag.assert(registerValue(small, &small) == 3)
    Swag.assert(small.value == 9)
    var odd: Odd = Odd{a: 4, b: 5, c: 6}
    Swag.assert(cOdd(odd, &odd) == 4)
    Swag.assert(odd.a == 9)
    var value: Value = Value{a: 7}
    Swag.assert(inlineRead(value) == 7)
}

#[Swag.NoInline]
func replaceFrom(value: Value)->Value
{
    var result: retval
    Swag.assert(&result != &value)
    result.a = 41
    result.b = value.a
    result.c = value.b
    return result
}

#test
{
    var value: Value = Value{a: 1, b: 2, c: 3}
    value = replaceFrom(value)
    Swag.assert(value.a == 41 and value.b == 1 and value.c == 2)
}

struct Header
{
    target: *u64
    a, b:   u64
}

#[Swag.NoInline]
func makeHeader(target: *u64)->Header => Header{target, 3, 5}

#[Swag.NoInline]
func writeHeaderTarget(header: Header)->u64
{
    header.target[] = 17
    return header.a + header.b
}

#[Swag.NoInline]
func writeSlice(bytes: [..] u8)
{
    bytes[0] = 19
}

#test
{
    var target: u64
    let header = makeHeader(&target)
    Swag.assert(writeHeaderTarget(header) == 8)
    Swag.assert(writeHeaderTarget(Header{&target, 7, 11}) == 18)
    Swag.assert(target == 17)
    var bytes: [8] u8
    writeSlice(bytes[2 until 5])
    Swag.assert(bytes[2] == 19)
}

#test
{
    var value: Value = Value{a: 1, b: 2, c: 3}
    let callback     = &cValue
    Swag.assert(callback(value, &value) == 1)
    Swag.assert(value.a == 13)
}

#[Swag.NoInline]
func readHeaderAddress(header: const *Header)->u64 => header.a + header.b

#[Swag.NoInline]
func writePayloadAfterReadingHeader(header: Header)->u64
{
    let sum = readHeaderAddress(&header)
    header.target[] = 23
    return sum
}

#[Swag.NoInline]
func readSliceAddress(bytes: const *[..] u8)->u64 => bytes[].count

#[Swag.NoInline]
func writeSliceAfterReadingHeader(bytes: [..] u8)->u64
{
    let count = readSliceAddress(&bytes)
    bytes[0] = 29
    return count
}

#test
{
    var target: u64
    let header: Header = Header{&target, 5, 7}
    Swag.assert(writePayloadAfterReadingHeader(header) == 12)
    Swag.assert(target == 23)
    var bytes: [4] u8
    Swag.assert(writeSliceAfterReadingHeader(bytes) == 4)
    Swag.assert(bytes[0] == 29)
}

struct TextHeader
{
    text:    string
    padding: u64
}

impl TextHeader
{
    #[Swag.Implicit, Swag.Inline]
    mtd const opCast()->string => .text
}

var counter: u64

#[Swag.NoInline]
func updateCounter(text: string)->u64
{
    counter += 1
    return text.count
}

#[Swag.NoInline]
func useTextHeader(header: TextHeader)->u64 => updateCounter(header.text)

#[Swag.NoInline]
func makeText()->string => "result"

#[Swag.NoInline]
func forwardText()->string => makeText()

#[Swag.NoInline]
func readValueAddress(value: const *Value)->u64 => value.a

#[Swag.Inline]
func makeInlineValue()->Value
{
    var result: retval
    result.a = 1
    Swag.assert(readValueAddress(&result) == 1)
    return result
}

#[Swag.NoInline]
func makeTextUsingInline()->string
{
    let value = makeInlineValue()
    var sum: u64
    for index in reversed(value.a) do
        sum += index
    return value.a == 1 and sum == 0 ? "result" : "other"
}

#test
{
    let header: TextHeader = TextHeader{text: "borrow"}
    Swag.assert(useTextHeader(header) == 6)
    Swag.assert(updateCounter(header) == 6)
    Swag.assert(updateCounter(forwardText()) == 6)
    Swag.assert(updateCounter(makeTextUsingInline()) == 6)
}

#[Swag.NoInline]
func readTemporaryView(values: const [..] string)->u64
{
    counter += 1
    return values[0].count
}

#[Swag.NoInline]
func passTemporaryView(value: string)->u64 => readTemporaryView([value])

#test
{
    Swag.assert(passTemporaryView("view") == 4)
}

interface WriteSink
{
    mtd write()
}

struct WriteCounter
{
    count: u64
}

impl WriteSink for WriteCounter
{
    mtd impl write() { .count += 1 }
}

struct SinkOwner
{
    sink: WriteSink?
}

impl SinkOwner
{
    mtd opDrop() {}
}

#[Swag.NoInline]
func writeSink(sink: WriteSink?) { sink?.write() }

#[Swag.NoInline]
func writeSeparateSink(owner: *SinkOwner, other: const *Value)->u64
{
    let sink = owner.sink
    writeSink(sink)
    return other.a
}

#[Swag.NoInline]
func readWithSeparateSink(value: Value, owner: *SinkOwner)->u64
{
    return writeSeparateSink(owner, &value)
}

#test
{
    var counter: WriteCounter
    var owner:   SinkOwner = SinkOwner{sink: &counter}
    let value:   Value     = Value{a: 37}
    let result             = readWithSeparateSink(value, &owner)
    Swag.assert(result == 37)
    Swag.assert(counter.count == 1)
}

#[Swag.NoInline]
func writeSelectedSink(first: *SinkOwner, second: *SinkOwner, other: const *Value, chooseSecond: bool)->u64
{
    var sink = first.sink
    if chooseSecond do
        sink = second.sink
    writeSink(sink)
    return other.a
}

#[Swag.NoInline]
func readWithSelectedSink(value: Value, first: *SinkOwner, second: *SinkOwner)->u64
{
    return writeSelectedSink(first, second, &value, true)
}

#test
{
    var firstCounter, secondCounter: WriteCounter
    var first:  SinkOwner = SinkOwner{sink: &firstCounter}
    var second: SinkOwner = SinkOwner{sink: &secondCounter}
    let value:  Value     = Value{a: 41}
    let result            = readWithSelectedSink(value, &first, &second)
    Swag.assert(result == 41)
    Swag.assert(firstCounter.count == 0)
    Swag.assert(secondCounter.count == 1)
}

#[Swag.NoInline]
func forwardOptionalText(value: string?)->u64 => updateCounter(value orelse "fallback")

#[Swag.NoInline]
func forwardSelectedText(value: string, useValue: bool)->u64
{
    return updateCounter(useValue ? value : "fallback")
}

#test
{
    Swag.assert(forwardOptionalText("value") == 5)
    Swag.assert(forwardOptionalText(null) == 8)
    Swag.assert(forwardSelectedText("value", true) == 5)
    Swag.assert(forwardSelectedText("value", false) == 8)
}

#[Swag.NoInline]
func decodeReadAddress(bits: u64)->const *Value => cast(const *Value, bits)

#[Swag.NoInline]
func readEncodedValue(value: Value)->u64 => decodeReadAddress(cast(u64, &value)).a

#test
{
    let value: Value = Value{a: 61}
    let result       = readEncodedValue(value)
    Swag.assert(result == 61)
}

#[Swag.NoInline]
func readTypedEncoded(values: u64...)->u64 => cast(const *Value, values[1]).a

#[Swag.NoInline]
func readUntypedEncoded(values: ...)->u64
{
    let bits = assume cast(u64, values[1])
    return cast(const *Value, bits).a
}

#[Swag.NoInline]
func readPackedEncoding(value: Value)->u64
{
    let first  = readTypedEncoded(0, cast(u64, &value))
    let second = readUntypedEncoded(0, cast(u64, &value))
    return first + second
}

#test
{
    let value: Value = Value{a: 67}
    let result       = readPackedEncoding(value)
    Swag.assert(result == 134)
}

struct EncodedSelf { address, padding1, padding2: u64 }
impl EncodedSelf
{
    #[Swag.Implicit]
    mtd opSet(seed: u64)
    {
        .address  = cast(u64, me)
        .padding1 = seed
    }
}

#[Swag.NoInline]
func makeEncodedSelf()->EncodedSelf
{
    var result: retval = 1'u64
    return result
}

#[Swag.NoInline]
func mutateEncodedSelf(value: EncodedSelf)->u64
{
    cast(*EncodedSelf, value.address).padding1 = 79
    return value.padding1
}

#test
{
    let result = mutateEncodedSelf(#copy makeEncodedSelf())
    Swag.assert(result == 1)
}

// Relaying a pointer preserves writes to its slot, not to the object it contains.
struct PointerSlot { target: *Value? }

#[Swag.NoInline]
func clearPointerSlot(slot: *PointerSlot) { slot.target = null }

#[Swag.NoInline]
func relayClearPointerSlot(slot: *PointerSlot) { clearPointerSlot(slot) }

#[Swag.NoInline]
func readAndClearPointerSlot(value: Value, slot: *PointerSlot)->u64
{
    relayClearPointerSlot(slot)
    return value.a
}

#test
{
    var value: Value       = Value{a: 83}
    var slot:  PointerSlot = PointerSlot{target: &value}
    let result             = readAndClearPointerSlot(value, &slot)
    Swag.assert(result == 83)
    Swag.assert(slot.target == null)
}

#[Swag.NoInline]
func makePlainValue()->Value => {a: 89}

#[Swag.NoInline]
func relayPlainValue()->Value => makePlainValue()

#test
{
    var other: u64
    let direct  = writeOther(makePlainValue(), &other)
    let relayed = writeOther(relayPlainValue(), &other)
    Swag.assert(direct == 89 and relayed == 89 and other == 12)
}

#[Swag.NoInline]
func invokeLiteral(callback: func(value: Value)->u64)->u64 => callback({a: 127})

#test
{
    let result = invokeLiteral(&read)
    Swag.assert(result == 127)
}

#[Swag.CallingConvention(.C)]
alias CValueCallback = func(value: Value, target: *Value)->u64

#test
{
    let callback: CValueCallback = &cValue
    var value:    Value = Value{a: 131}
    let result = callback(value, &value)
    Swag.assert(result == 131 and value.a == 13)
}

// Indexing a pointer changes the addressed slot without following its contents.
#[Swag.NoInline]
func clearIndexedPointerSlot(slot: [*] PointerSlot, index: u64)
{
    slot[index].target = null
}

#[Swag.NoInline]
func clearOffsetPointerSlot(slot: [*] PointerSlot, index: u64)
{
    (slot + index)[].target = null
}

#[Swag.NoInline]
func readAndClearIndexedPointerSlot(value: Value, slot: [*] PointerSlot)->u64
{
    clearIndexedPointerSlot(slot, 0)
    return value.a
}

#[Swag.NoInline]
func readAndClearOffsetPointerSlot(value: Value, slot: [*] PointerSlot)->u64
{
    clearOffsetPointerSlot(slot, 0)
    return value.a
}

#test
{
    var value: Value       = Value{a: 137}
    var slot:  PointerSlot = PointerSlot{target: &value}
    let result             = readAndClearIndexedPointerSlot(value, cast([*] PointerSlot, &slot))
    Swag.assert(result == 137 and slot.target == null)
}

#test
{
    var value: Value       = Value{a: 139}
    var slot:  PointerSlot = PointerSlot{target: &value}
    let result             = readAndClearOffsetPointerSlot(value, cast([*] PointerSlot, &slot))
    Swag.assert(result == 139 and slot.target == null)
}

struct DepthValue
{
    value, padding: u64
    target:         *u64?
}
impl DepthValue
{
    mtd opPostCopy() { .target = &.value }
}
struct DepthEntry
{
    target: *u64?
    stamp:  u64
}
struct DepthTable { entry: *DepthEntry }

#[Swag.NoInline]
func storeAndClearDeepAlias(table: *DepthTable, value: DepthValue)->u64
{
    let entry = table.entry
    entry.target = value.target
    entry.stamp  = 157
    entry.target = null
    return value.value
}

func compileTimeDeepCopy()->bool
{
    var entry: DepthEntry
    var table: DepthTable = DepthTable{entry: &entry}
    var value: DepthValue = DepthValue{value: 163}
    let result = storeAndClearDeepAlias(&table, #copy value)
    return result == 163 and entry.stamp == 157 and entry.target == null
}

const COMPILE_TIME_DEEP_COPY = #run compileTimeDeepCopy()

#test
{
    Swag.assert(COMPILE_TIME_DEEP_COPY)
    Swag.assert(compileTimeDeepCopy())
}
