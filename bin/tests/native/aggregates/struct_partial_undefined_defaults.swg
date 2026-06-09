#global fileprivate

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

    kind: Kind = undefined
    from: *void
}

struct PartialUndefinedDefaults
{
    required: s32 = undefined
    label:    string = "ready"
    value:    s32 = 17
    enabled:  bool
}

struct AllUndefinedDefaults
{
    x: s32 = undefined
    y: s32 = undefined
}

const PARTIAL_UNDEFINED_CONST: PartialUndefinedDefaults
const ALL_UNDEFINED_CONST: AllUndefinedDefaults

#assert(PARTIAL_UNDEFINED_CONST.required == 0)
#assert(PARTIAL_UNDEFINED_CONST.value == 17)
#assert(PARTIAL_UNDEFINED_CONST.enabled == false)
#assert(ALL_UNDEFINED_CONST.x == 0)
#assert(ALL_UNDEFINED_CONST.y == 0)

#test
{
    var event = PartialUndefinedEvent{}
    event.kind = .Changed

    @assert(event.kind == PartialUndefinedEvent.Kind.Changed)
    @assert(event.accepted == false)
    @assert(event.from == null)
}

#test
{
    var value = PartialUndefinedDefaults{}
    value.required = 25

    @assert(value.required == 25)
    @assert(value.label[0] == 'r''u8)
    @assert(value.value == 17)
    @assert(value.enabled == false)
}

#test
{
    @assert(PARTIAL_UNDEFINED_CONST.label[0] == 'r''u8)
}

#test
{
    var value: PartialUndefinedDefaults = {}
    value.required = 31

    @assert(value.required == 31)
    @assert(value.label[0] == 'r''u8)
    @assert(value.value == 17)
    @assert(value.enabled == false)
}

#test
{
    var value: PartialUndefinedDefaults
    value.required = 49

    @assert(value.required == 49)
    @assert(value.label[0] == 'r''u8)
    @assert(value.value == 17)
    @assert(value.enabled == false)
}
