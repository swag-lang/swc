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
