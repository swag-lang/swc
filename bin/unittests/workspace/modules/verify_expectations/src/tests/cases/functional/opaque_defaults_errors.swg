#global if #command == Swag.CompilerCommand.Test
#global private

// The integrated sources share the address used by the provider's default.
const OPAQUE_POINTER_CONSTANT: StaticApi.OpaqueDefaultPointer = {}
var   opaquePointerGlobal:      StaticApi.OpaqueDefaultPointer
var   opaquePointerArrayGlobal: [2] StaticApi.OpaqueDefaultPointer

#test
{
    Swag.require(OPAQUE_POINTER_CONSTANT.isDefault())
    Swag.require(opaquePointerGlobal.isDefault())
    Swag.require(opaquePointerArrayGlobal[0].isDefault())
    Swag.require(opaquePointerArrayGlobal[1].isDefault())
}

// Hiding fields must not manufacture a complete zero default for a required source field.
var opaqueRequiredGlobal: StaticApi.OpaqueRequiredDefault     // swc-expected-error {{sema_err_type_requires_init}}

func opaqueRequiredEmptyLiteral()
{
    let value = StaticApi.OpaqueRequiredDefault{}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}
