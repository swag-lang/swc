#global private

const UNION_TARGET = "union-pointer-target"

union TextDefault
{
    ignored: u64
    text:    string = "union-default-text"
}

union PointerDefault
{
    number:  u64
    pointer: const [*] u8 = UNION_TARGET.buffer
}

union IntegerAlternative
{
    text:  string = "inactive-string"
    words: [2] u64
}

union PartialOverwrite
{
    whole:   u64
    low:     u32
    pointer: const [*] u8 = UNION_TARGET.buffer
}

union PartialDefault
{
    whole:   u64
    pointer: const [*] u8 = UNION_TARGET.buffer
    byte:    u8 = 0x55
}

union ReplacedDefault
{
    pointer: const [*] u8 = UNION_TARGET.buffer
    byte:    u8  = 0x55
    whole:   u64 = 67
}

union ArrayPartialDefault
{
    whole:   u64
    pointer: const [*] u8 = UNION_TARGET.buffer
    byte:    u8 = 0x55
}

#[Swag.NoInline]
func unionRuntimeAddress()->u64 => cast(u64, UNION_TARGET.buffer)

struct NestedDefaults
{
    text:    TextDefault
    pointer: PointerDefault
}

struct NestedIntegerAlternative
{
    value: IntegerAlternative
}

struct RuntimeDefaultSet
{
    value:    PartialDefault
    observed: u64
}

impl RuntimeDefaultSet
{
    #[Swag.ConstExpr]
    mtd opSet(seed: u64) { .observed = .value.whole ^ seed }
}

struct FullRuntimeDefaultSet
{
    value:    PartialDefault
    observed: u64
}

impl FullRuntimeDefaultSet
{
    #[Swag.ConstExpr, Swag.FullInit]
    mtd opSet(seed: u64)
    {
        .value    = {whole: 0}
        .observed = seed
    }
}

const TEXT_CONSTANT:     TextDefault           = {}
const POINTER_CONSTANT:  PointerDefault        = {}
const INTEGER_CONSTANT:  IntegerAlternative    = {words: [17, 23]}
const NUMBER_CONSTANT:   PointerDefault        = {number: 37}
const TEXT_ARRAY:        [2] TextDefault       = [{text: "first"}, {}]
const POINTER_MATRIX:    [2, 2] PointerDefault = [[{number: 41}]]
const REPLACED_CONSTANT: PartialDefault        = {whole: 0}
const RESTORED_POINTER:  PartialDefault        = {pointer: UNION_TARGET.buffer}
const REPLACED_ARRAY:    [2] PartialDefault    = [{whole: 71}, {whole: 73}]
const REPLACED_DEFAULT:  ReplacedDefault       = {}

var globalText:          TextDefault
var globalPointer:       PointerDefault
var globalNested:        NestedDefaults
var globalInteger:       IntegerAlternative       = {words: [29, 31]}
var globalIntegerArray:  [2] IntegerAlternative   = [{words: [97, 101]}, {words: [103, 107]}]
var globalNestedInteger: NestedIntegerAlternative = NestedIntegerAlternative{value: {words: [109, 113]}}
var globalReplaced:      PartialDefault           = {whole: 79}

#test
{
    var text:    TextDefault
    var pointer: PointerDefault
    Swag.require(text.text == "union-default-text")
    Swag.require(pointer.pointer == UNION_TARGET.buffer)
    Swag.require(TEXT_CONSTANT.text == "union-default-text")
    Swag.require(POINTER_CONSTANT.pointer == UNION_TARGET.buffer)
    Swag.require(globalText.text == "union-default-text")
    Swag.require(globalPointer.pointer == UNION_TARGET.buffer)
    Swag.require(globalNested.text.text == "union-default-text")
    Swag.require(globalNested.pointer.pointer == UNION_TARGET.buffer)
}

#test
{
    var text    = TextDefault{text: "changed"}
    var pointer = PointerDefault{number: 43}
    Swag.require(text.text == "changed")
    Swag.require(pointer.number == 43)
    text    = {}
    pointer = {}
    Swag.require(text.text == "union-default-text")
    Swag.require(pointer.pointer == UNION_TARGET.buffer)
    text.text      = "changed-again"
    pointer.number = 47
    Swag.init(&text)
    Swag.init(&pointer)
    Swag.require(text.text == "union-default-text")
    Swag.require(pointer.pointer == UNION_TARGET.buffer)
}

// Integer alternatives must neither inspect inactive strings nor inherit their relocations.
#test
{
    let value = IntegerAlternative{words: [53, 59]}
    Swag.require(value.words[0] == 53)
    Swag.require(value.words[1] == 59)
    Swag.require(INTEGER_CONSTANT.words[0] == 17)
    Swag.require(INTEGER_CONSTANT.words[1] == 23)
    Swag.require(globalInteger.words[0] == 29)
    Swag.require(globalInteger.words[1] == 31)
    Swag.require(globalIntegerArray[0].words[0] == 97)
    Swag.require(globalIntegerArray[0].words[1] == 101)
    Swag.require(globalIntegerArray[1].words[0] == 103)
    Swag.require(globalIntegerArray[1].words[1] == 107)
    Swag.require(globalNestedInteger.value.words[0] == 109)
    Swag.require(globalNestedInteger.value.words[1] == 113)
    Swag.require(NUMBER_CONSTANT.number == 37)
    let partial = PartialOverwrite{low: 61}
    Swag.require(partial.low == 61)
    Swag.require(partial.whole == ((unionRuntimeAddress() & 0xFFFFFFFF00000000) | 61))
}

#test
{
    Swag.require(TEXT_ARRAY[0].text == "first")
    Swag.require(TEXT_ARRAY[1].text == "union-default-text")
    Swag.require(POINTER_MATRIX[0, 0].number == 41)
    Swag.require(POINTER_MATRIX[0, 1].pointer == UNION_TARGET.buffer)
    Swag.require(POINTER_MATRIX[1, 0].pointer == UNION_TARGET.buffer)
    Swag.require(POINTER_MATRIX[1, 1].pointer == UNION_TARGET.buffer)
    var values: [2] NestedDefaults
    values[1].text.text = "changed"
    Swag.init(&values)
    Swag.require(values[0].text.text == "union-default-text")
    Swag.require(values[1].text.text == "union-default-text")
    Swag.require(values[0].pointer.pointer == UNION_TARGET.buffer)
    Swag.require(values[1].pointer.pointer == UNION_TARGET.buffer)
}

// A partial pointer overwrite is evaluated against the eventual runtime address.
#test
{
    var value: PartialDefault
    Swag.require(value.whole == ((unionRuntimeAddress() & 0xFFFFFFFFFFFFFF00) | 0x55))
    value.byte = 0
    value      = {}
    Swag.require(value.whole == ((unionRuntimeAddress() & 0xFFFFFFFFFFFFFF00) | 0x55))
    value.byte = 0
    Swag.init(&value)
    Swag.require(value.whole == ((unionRuntimeAddress() & 0xFFFFFFFFFFFFFF00) | 0x55))
    var values: [2] ArrayPartialDefault
    Swag.require(values[0].whole == value.whole)
    Swag.require(values[1].whole == value.whole)
    values[0].byte = 0
    Swag.init(&values)
    Swag.require(values[0].whole == value.whole)
    Swag.require(values[1].whole == value.whole)
}

// Full overwrites remove every runtime-dependent byte, even after default resolution.
#test
{
    let resolved: PartialDefault
    Swag.require(resolved.whole == ((unionRuntimeAddress() & 0xFFFFFFFFFFFFFF00) | 0x55))
    const replaced: PartialDefault = {whole: 83}
    Swag.require(replaced.whole == 83)
    Swag.require(REPLACED_CONSTANT.whole == 0)
    Swag.require(RESTORED_POINTER.pointer == UNION_TARGET.buffer)
    Swag.require(REPLACED_ARRAY[0].whole == 71)
    Swag.require(REPLACED_ARRAY[1].whole == 73)
    Swag.require(REPLACED_DEFAULT.whole == 67)
    Swag.require(globalReplaced.whole == 79)
}

// Constant-set folding must not substitute zero storage for a runtime receiver default.
#test
{
    let value    = cast(RuntimeDefaultSet, 7'u64)
    let expected = (unionRuntimeAddress() & 0xFFFFFFFFFFFFFF00) | 0x55
    Swag.require(value.value.whole == expected)
    Swag.require(value.observed == (expected ^ 7))

    let resolved: FullRuntimeDefaultSet
    Swag.require(resolved.value.whole == expected)
    const initialized = cast(FullRuntimeDefaultSet, 89'u64)
    Swag.require(initialized.value.whole == 0)
    Swag.require(initialized.observed == 89)
}
