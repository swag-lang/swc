#global private

var Calls:   u32
var Storage: [3] s32 = [4, 5, 6]

#[Swag.NoInline]
func nextSlice()->[..] s32
{
    Calls += 1
    return Storage
}

#[Swag.Inline]
func explicitSlice(values: [..] s32)->u64
{
    #assert(#typeof(values) == [..] s32)
    values[1] += 10
    return values.count
}

func automaticSlice(values: [..] s32)->u64
{
    #assert(#typeof(values) == [..] s32)
    values[1] += 10
    return values.count
}

#[Swag.NoInline]
func writeFirst(values: [*] s32)
{
    values[0] += 1
}

#[Swag.Inline]
func explicitBuffer(values: [..] s32)->u64
{
    writeFirst(values.buffer)
    return values.count
}

func automaticBuffer(values: [..] s32)->u64
{
    writeFirst(values.buffer)
    return values.count
}

#[Swag.Inline]
func singleBuffer(values: [..] s32)
{
    writeFirst((values).buffer)
}

#[Swag.Inline]
func constBuffer(values: const [..] s32)->s32
{
    #assert(#typeof(values.buffer) == const [*] s32)
    return values.buffer[0]
}

#test
{
    var data: [3] s32 = [1, 2, 3]
    let explicitCount = explicitBuffer(data)
    let automaticCount = automaticBuffer(data)
    Swag.assert(explicitCount == 3 and automaticCount == 3)
    Swag.assert(data[0] == 3)

    let view: [..] s32 = data
    singleBuffer(view)
    Swag.assert(data[0] == 4)
    Swag.assert(constBuffer(view) == 4)

    Calls = 0
    Storage = [4, 5, 6]
    let returnedCount = explicitBuffer(nextSlice())
    Swag.assert(returnedCount == 3 and Calls == 1 and Storage[0] == 5)
}

#[Swag.Inline]
func(T) genericSlice(values: [..] T)->u64
{
    #assert(#typeof(values) == [..] T)
    return values.count
}

#[Swag.Inline]
func nullableSlice(values: [..] s32?)->bool
{
    #assert(#typeof(values) == [..] s32?)
    return values == null
}

#test
{
    var data: [3] s32 = [1, 2, 3]
    Swag.assert(explicitSlice(data) == 3)
    Swag.assert(automaticSlice(data) == 3)
    Swag.assert(data[1] == 22)
    Swag.assert(genericSlice(data) == 3)

    let view: [..] s32 = data
    Swag.assert(explicitSlice(view) == 3)
    Swag.assert(view.count == 3 and data[1] == 32)
    Swag.assert(not nullableSlice(view))
    Swag.assert(nullableSlice(null))

    Calls   = 0
    Storage = [4, 5, 6]
    Swag.assert(explicitSlice(nextSlice()) == 3)
    Swag.assert(Calls == 1 and Storage[1] == 15)
}

struct Converted
{
    length: u64
    first:  u8
}

var Conversions: u32

impl Converted
{
    #[Swag.Implicit]
    #[Swag.NoInline]
    mtd opSet(value: string)
    {
        Conversions += 1
        .length     = value.count
        .first      = value[0]
    }
}

#[Swag.NoInline]
func nextText()->string
{
    Calls += 1
    return "xyz"
}

#[Swag.Inline]
func convertedTotal(values: const [..] Converted)->u64
{
    var total: u64
    for value in values do
        total += value.length + value.first
    return total
}

#test
{
    Conversions = 0
    Swag.assert(convertedTotal(["ab", "cde"]) == 201)
    Swag.assert(Conversions == 2)

    Calls = 0
    Swag.assert(convertedTotal([nextText(), "ab"]) == 222)
    Swag.assert(Calls == 1 and Conversions == 4)
}
