#global fileprivate

// Array dimensions must be positive integers; negative values are rejected in every type context.
var a: [-1] s32                   // swc-expected-error {{sema_err_array_dim_negative}}
var b: [-100] bool                // swc-expected-error {{sema_err_array_dim_negative}}

func bad(p: [-2] s32) {}          // swc-expected-error {{sema_err_array_dim_negative}}
