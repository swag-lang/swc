#global if #command == Swag.CompilerCommand.Test
#global private

using StaticApi.OpaqueAttributeCollision

#test
{
    resetDrops()
    scope
    {
        var value: Value
        Swag.require(value.isDefault())
        value.arm()
    }
    Swag.require(drops() == 1)
}

#test
{
    let value    = Value{}
    let scalar   = Scalar{}
    let required = cast(Required, "ready")
    let tagged   = Tagged{37}
    Swag.require(value.isDefault())
    Swag.require(scalar.isDefault())
    Swag.require(required.isReady())
    Swag.require(tagged.value == 37)
}

func rejectMissingCollisionDefault()
{
    let value = Required{}     // swc-expected-error {{sema_err_type_requires_init}}
}
