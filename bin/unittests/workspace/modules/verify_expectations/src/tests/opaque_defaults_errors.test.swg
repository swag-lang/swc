#global if #command == Swag.CompilerCommand.Test
#global private

// An address to private provider data cannot be materialized in consumer constant storage.
const OPAQUE_RUNTIME_CONSTANT: StaticApi.OpaqueDefaultPointer = {}     // swc-expected-error {{sema_err_expr_not_const}}
var opaqueRuntimeGlobal:      StaticApi.OpaqueDefaultPointer           // swc-expected-error {{sema_err_expr_not_const}}
var opaqueRuntimeArrayGlobal: [2] StaticApi.OpaqueDefaultPointer       // swc-expected-error {{sema_err_expr_not_const}}

// Hiding fields must not manufacture a complete zero default for a required source field.
var opaqueRequiredGlobal: StaticApi.OpaqueRequiredDefault     // swc-expected-error {{sema_err_type_requires_init}}

func opaqueRequiredEmptyLiteral()
{
    let value = StaticApi.OpaqueRequiredDefault{}     // swc-expected-error {{sema_err_type_requires_init}}
}
