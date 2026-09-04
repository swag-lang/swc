#global private

struct PartialUndefinedBase
{
    accepted: bool
}

struct PartialUndefinedEvent
{
    using base: PartialUndefinedBase

    enum Kind
    {
        Changed
        Closed
    }

    kind: Kind
    from: *void?
}

struct PartialUndefinedDefaults
{
    required: s32
    label:    string = "ready"
    value:    s32    = 17
    enabled:  bool
}

struct AllUndefinedDefaults
{
    x: s32
    y: s32
}

enum PartialSliceNeed
{
    Nothing
    Value
}

struct PartialSliceDescriptor
{
    id:     string
    label:  string
    need:   PartialSliceNeed = .Nothing
    hidden: bool
}

struct PartialSliceLabels
{
    one:   string = "One"
    two:   string = "Two"
    three: string = "Three"
    four:  string = "Four"
    five:  string = "Five"
    six:   string = "Six"
    seven: string = "Seven"
    eight: string = "Eight"
}

func countHiddenDescriptors(values: const [..] PartialSliceDescriptor)->u64
{
    var result: u64
    for &value in values where value.hidden do
        result += 1
    return result
}

var g_PartialSliceLabels: PartialSliceLabels

#[Swag.NoInline]
func runtimeDescriptorLabels()->const *PartialSliceLabels => &g_PartialSliceLabels

const PARTIAL_UNDEFINED_CONST: PartialUndefinedDefaults
const ALL_UNDEFINED_CONST:     AllUndefinedDefaults

#assert(PARTIAL_UNDEFINED_CONST.required == 0)
#assert(PARTIAL_UNDEFINED_CONST.value == 17)
#assert(PARTIAL_UNDEFINED_CONST.enabled == false)
#assert(ALL_UNDEFINED_CONST.x == 0)
#assert(ALL_UNDEFINED_CONST.y == 0)

#test
{
    var event = PartialUndefinedEvent{}
    event.kind = .Changed

    Swag.assert(event.kind == PartialUndefinedEvent.Kind.Changed)
    Swag.assert(event.accepted == false)
    Swag.assert(event.from == null)
}

#test
{
    var value = PartialUndefinedDefaults{}
    value.required = 25

    Swag.assert(value.required == 25)
    Swag.assert(value.label[0] == 'r'u8)
    Swag.assert(value.value == 17)
    Swag.assert(value.enabled == false)
}

#test
{
    Swag.assert(PARTIAL_UNDEFINED_CONST.label[0] == 'r'u8)
}

#test
{
    var value: PartialUndefinedDefaults = {}
    value.required = 31

    Swag.assert(value.required == 31)
    Swag.assert(value.label[0] == 'r'u8)
    Swag.assert(value.value == 17)
    Swag.assert(value.enabled == false)
}

#test
{
    var value: PartialUndefinedDefaults
    value.required = 49

    Swag.assert(value.required == 49)
    Swag.assert(value.label[0] == 'r'u8)
    Swag.assert(value.value == 17)
    Swag.assert(value.enabled == false)
}

// Contextually typed aggregate literals use the same default initialization as named locals,
// including when a temporary array is passed directly as a slice.
#test
{
    let descriptors: const [..] PartialSliceDescriptor = [
        {"one",   runtimeDescriptorLabels().one,   .Value},
        {"two",   runtimeDescriptorLabels().two,   .Value},
        {"three", runtimeDescriptorLabels().three, .Value},
        {"four",  runtimeDescriptorLabels().four,  .Value},
        {"five",  runtimeDescriptorLabels().five,  .Value},
        {"six",   runtimeDescriptorLabels().six,   .Value},
        {"seven", runtimeDescriptorLabels().seven, .Value},
        {"eight", runtimeDescriptorLabels().eight, .Value}]
    Swag.assert(countHiddenDescriptors(descriptors) == 0)
}
