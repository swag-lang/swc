#global private

// A named constant used as an aggregate-literal field value, where the field type converts
// through a set operator. The literal is not folded — the operator has to run — so the field
// node is substituted by the cast that calls it, and the constant it carries has to survive
// that substitution. It did not: a nullable operator parameter made 'opSet' run with an
// uninitialized argument (an empty string), and a non-nullable one asserted in code
// generation because the identifier had lost its constant.

const KEY  = "text"
const TKEY: string = "text"
const NUM  = 42

struct NullableName
{
    length: u64
}

impl NullableName
{
    #[Swag.Implicit]
    mtd opSet(value: #null string) { .length = @countof(value) }
}

struct StrictName
{
    length: u64
}

impl StrictName
{
    #[Swag.Implicit]
    mtd opSet(value: string) { .length = @countof(value) }
}

struct Counted
{
    value: u64
}

impl Counted
{
    #[Swag.Implicit]
    mtd opSet(value: s32) { .value = cast(u64) value }
}

struct Row
{
    id:   u64 = 99
    name: NullableName
}

struct StrictRow
{
    id:   u64 = 99
    name: StrictName
}

struct SoloRow
{
    name: NullableName
}

struct CountedPair
{
    first:  Counted
    second: Counted
}

func nullableLength(value: #null string)->u64 => @countof(value)

#test
{
    // The same constant is correct in every position that already worked.
    @assert(nullableLength(KEY) == 4)
    @assert((cast(NullableName) KEY).length == 4)

    var row: Row = undefined
    row.id   = 1
    row.name = KEY
    @assert(row.name.length == 4)
}

#test
{
    // Positional and named literal slots, untyped and typed constants, literal and local.
    let local: string = KEY
    @assert(Row{1, KEY}.name.length == 4)
    @assert(Row{1, TKEY}.name.length == 4)
    @assert(Row{1, "text"}.name.length == 4)
    @assert(Row{1, local}.name.length == 4)
    @assert(Row{name: KEY}.name.length == 4)
    @assert(SoloRow{KEY}.name.length == 4)
}

#test
{
    // A non-nullable operator parameter takes a different path through the cast, and has to
    // reach the same result.
    @assert(StrictRow{1, KEY}.name.length == 4)
    @assert(StrictRow{name: TKEY}.name.length == 4)
}

#test
{
    // The same shape with a numeric constant, and nested inside an array literal.
    @assert(CountedPair{NUM, 7}.first.value == 42)
    @assert(CountedPair{NUM, 7}.second.value == 7)

    let rows = [Row{1, KEY}, Row{2, TKEY}]
    @assert(rows[0].name.length == 4)
    @assert(rows[1].name.length == 4)
}
