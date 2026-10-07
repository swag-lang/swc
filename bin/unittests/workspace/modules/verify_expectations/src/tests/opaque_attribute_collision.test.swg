#global if #command == Swag.CompilerCommand.Test
#global private

using StaticApi.OpaqueAttributeCollision

#test
{
    resetDrops()
    {
        var value: Value
        Swag.assert(value.isDefault())
        value.arm()
    }
    Swag.assert(drops() == 1)
}

#test
{
    let value    = Value{}
    let scalar   = Scalar{}
    let required = cast(Required, "ready")
    let tagged   = Tagged{37}
    Swag.assert(value.isDefault())
    Swag.assert(scalar.isDefault())
    Swag.assert(required.isReady())
    Swag.assert(tagged.value == 37)
}

func rejectMissingCollisionDefault()
{
    let value = Required{}     // swc-expected-error {{sema_err_type_requires_init}}
}
