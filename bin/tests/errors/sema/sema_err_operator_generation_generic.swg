#[Swag.Operators(opEquals)] // swc-expected-error {{sema_err_operator_generation_generic}}
struct(T) GeneratedGenericOperator
{
    value: T
}
