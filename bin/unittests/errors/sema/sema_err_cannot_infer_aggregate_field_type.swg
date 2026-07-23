#global private

enum InferEnum
{
    A
    B
}

// A minimal generic container with overloaded 'add' methods, reproducing the deferred-
// argument situation of 'Array'T.add()' without importing Core. The overload set forces
// the call argument's type to be deferred until an overload is selected.
struct(T) InferBox
{
    items: [1] T
}

impl InferBox
{
    mtd add(value: T) {}
    mtd add(value: #move T) {}
}

// An enum auto-member (`.A`) nested inside an aggregate literal that is itself a call
// argument cannot be inferred: the direct-argument deferral that resolves the aggregate
// from the selected overload's (generic) parameter type does not reach nested literal
// children. The compiler must report this, never assert.
func semaErrCannotInferAggregateFieldType()
{
    var data: InferBox'{ kind: InferEnum, name: string } = undefined
    data.add({.A, "x"})     // swc-expected-error {{sema_err_cannot_infer_aggregate_field_type}}
}
