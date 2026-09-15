#global private

#[Swag.DynCast]
struct DynamicLayoutValue { value: u64 }

union DynamicLayoutUnion
{
    // swc-expected-error@(+1) {{sema_err_dynamic_layout}}
    item: DynamicLayoutValue
    bits: [2] u64
}

struct DynamicLayoutOverlap
{
    // swc-expected-error@(+1) {{sema_err_dynamic_layout}}
    item: DynamicLayoutValue
    #[Swag.Offset("item")]
    bits: [2] u64
}
