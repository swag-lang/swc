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

    kind: Kind = undefined
    from: #null *void
}

struct PartialUndefinedDefaults
{
    required: s32    = undefined
    label:    string = "ready"
    value:    s32    = 17
    enabled:  bool
}

struct AllUndefinedDefaults
{
    x: s32 = undefined
    y: s32 = undefined
}

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
