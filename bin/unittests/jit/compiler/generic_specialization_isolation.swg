#global private

struct GenericIsolationWide
{
    first:  s64
    second: u8
}

func makeGenericIsolationWide(first: s64, second: u8)->GenericIsolationWide
{
    return {first: first, second: second}
}

struct(T, Pad: s32 = #sizeof(T) + 1) GenericIsolationEntry
{
    leading:  [Pad] u8
    value:    T
    trailing: [Pad + 1] u8
}

struct(T, Pad: s32 = #sizeof(T) + 1) GenericIsolationStore
{
    salt:    u64
    entries: [2] GenericIsolationEntry'(T, Pad)
}

impl GenericIsolationStore
{
    #[Swag.NoInline]
    mtd write(index: s32, value: T, lead: u8, trail: u8)
    {
        .entries[index].leading[Pad - 1] = lead
        .entries[index].value = value
        .entries[index].trailing[Pad] = trail
    }

    #[Swag.NoInline]
    mtd const get(index: s32)->T
    {
        return .entries[index].value
    }

    #[Swag.NoInline]
    mtd const lead(index: s32)->u8
    {
        return .entries[index].leading[Pad - 1]
    }

    #[Swag.NoInline]
    mtd const trail(index: s32)->u8
    {
        return .entries[index].trailing[Pad]
    }

    #[Swag.NoInline]
    mtd const snapshot(index: s32)->GenericIsolationEntry'(T, Pad)
    {
        let entry: GenericIsolationEntry'(T, Pad) = .entries[index]
        return entry
    }

    #[Swag.NoInline]
    mtd const checksum(index: s32)->u64
    {
        return .salt + cast(u64) .entries[index].leading[Pad - 1] + cast(u64) .entries[index].trailing[Pad]
    }
}

#[Swag.NoInline]
func(T, const Pad: s32) cloneEntry(store: const &GenericIsolationStore'(T, Pad), index: s32)->GenericIsolationEntry'(T, Pad)
{
    return store.snapshot(index)
}

#[Swag.NoInline]
func(T, const Pad: s32) readValue(store: const &GenericIsolationStore'(T, Pad), index: s32)->T
{
    let entry = store.snapshot(index)
    return entry.value
}

#test
{
    #assert(#sizeof(GenericIsolationEntry's32) != #sizeof(GenericIsolationEntry'(s32, 9)))
    #assert(#sizeof(GenericIsolationEntry's32) != #sizeof(GenericIsolationEntry'string))
    #assert(#sizeof(GenericIsolationEntry'GenericIsolationWide) != #sizeof(GenericIsolationEntry's32))

    var intsDefault: GenericIsolationStore's32
    var intsWide:    GenericIsolationStore'(s32, 9)
    var texts:       GenericIsolationStore'string = undefined
    var wides:       GenericIsolationStore'GenericIsolationWide

    intsDefault.salt = 100
    intsWide.salt = 200
    texts.salt = 300
    wides.salt = 400

    texts.write(0, "alpha", 10, 11)
    intsDefault.write(0, 42, 20, 21)
    wides.write(0, makeGenericIsolationWide(77, 7), 30, 31)
    intsWide.write(0, -99, 40, 41)

    intsWide.write(1, 1234, 42, 43)
    wides.write(1, makeGenericIsolationWide(88, 8), 32, 33)
    intsDefault.write(1, -7, 22, 23)
    texts.write(1, "beta", 12, 13)

    @assert(texts.get(0) == "alpha")
    @assert(texts.get(1) == "beta")
    @assert(texts.lead(0) == 10'u8)
    @assert(texts.trail(1) == 13'u8)
    @assert(texts.checksum(0) == 321)

    @assert(intsDefault.get(0) == 42)
    @assert(intsDefault.get(1) == -7)
    @assert(intsDefault.lead(1) == 22'u8)
    @assert(intsDefault.trail(0) == 21'u8)
    @assert(intsDefault.checksum(1) == 145)

    @assert(intsWide.get(0) == -99)
    @assert(intsWide.get(1) == 1234)
    @assert(intsWide.lead(0) == 40'u8)
    @assert(intsWide.trail(1) == 43'u8)
    @assert(intsWide.checksum(0) == 281)

    let wide0 = wides.get(0)
    let wide1 = wides.get(1)
    @assert(wide0.first == 77)
    @assert(wide0.second == 7'u8)
    @assert(wide1.first == 88)
    @assert(wide1.second == 8'u8)
    @assert(wides.lead(0) == 30'u8)
    @assert(wides.trail(1) == 33'u8)
    @assert(wides.checksum(1) == 465)
}

#test
{
    var intsDefault: GenericIsolationStore's32
    var intsWide:    GenericIsolationStore'(s32, 9)
    var texts:       GenericIsolationStore'string = undefined
    var wides:       GenericIsolationStore'GenericIsolationWide

    intsDefault.write(0, 5, 1, 2)
    texts.write(0, "left", 3, 4)
    wides.write(0, makeGenericIsolationWide(9, 10), 5, 6)
    intsWide.write(0, 77, 15, 16)

    texts.write(1, "right", 7, 8)
    intsDefault.write(1, 6, 9, 10)
    wides.write(1, makeGenericIsolationWide(11, 12), 13, 14)
    intsWide.write(1, 88, 17, 18)

    let intEntry = cloneEntry'(s32, #sizeof(s32) + 1)(&intsDefault, 1)
    let intWideEntry = cloneEntry'(s32, 9)(&intsWide, 0)
    let textEntry = cloneEntry'(string, #sizeof(string) + 1)(&texts, 0)
    let wideEntry = cloneEntry'(GenericIsolationWide, #sizeof(GenericIsolationWide) + 1)(&wides, 1)

    let intValue = readValue'(s32, #sizeof(s32) + 1)(&intsDefault, 0)
    let intWideValue = readValue'(s32, 9)(&intsWide, 1)
    let textValue = readValue'(string, #sizeof(string) + 1)(&texts, 1)
    let wideValue = readValue'(GenericIsolationWide, #sizeof(GenericIsolationWide) + 1)(&wides, 0)

    #assert(#typeof(intEntry) == GenericIsolationEntry's32)
    #assert(#typeof(intWideEntry) == GenericIsolationEntry'(s32, 9))
    #assert(#typeof(textEntry) == GenericIsolationEntry'string)
    #assert(#typeof(wideEntry) == GenericIsolationEntry'GenericIsolationWide)
    #assert(#typeof(intValue) == s32)
    #assert(#typeof(intWideValue) == s32)
    #assert(#typeof(textValue) == string)
    #assert(#typeof(wideValue) == GenericIsolationWide)

    @assert(intEntry.value == 6)
    @assert(intEntry.leading[4] == 9'u8)
    @assert(intEntry.trailing[5] == 10'u8)

    @assert(intWideEntry.value == 77)
    @assert(intWideEntry.leading[8] == 15'u8)
    @assert(intWideEntry.trailing[9] == 16'u8)

    @assert(textEntry.value == "left")
    @assert(texts.lead(0) == 3'u8)
    @assert(texts.trail(1) == 8'u8)

    @assert(wideEntry.value.first == 11)
    @assert(wideEntry.value.second == 12'u8)
    @assert(wides.lead(1) == 13'u8)
    @assert(wides.trail(0) == 6'u8)

    @assert(intValue == 5)
    @assert(intWideValue == 88)
    @assert(textValue == "right")
    @assert(wideValue.first == 9)
    @assert(wideValue.second == 10'u8)
}
