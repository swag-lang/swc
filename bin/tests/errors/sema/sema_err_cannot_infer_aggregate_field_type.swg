#global fileprivate
using Core

enum InferEnum
{
    A
    B
}

// An enum auto-member (`.A`) nested inside an aggregate literal that is itself a
// call argument cannot be inferred (the direct-argument deferral does not reach
// nested literal children). The compiler must report this, never assert.
#test
{
    var data: Array'{ kind: InferEnum, name: string }
    data.add({.A, "x"}) // swc-expected-error {{sema_err_cannot_infer_aggregate_field_type}}
}
