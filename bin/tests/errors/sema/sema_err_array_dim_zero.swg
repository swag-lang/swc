#global fileprivate

// A zero-sized array is rejected in every type context.
var a: [0] s32                   // swc-expected-error {{sema_err_array_dim_zero}}
var b: [0] bool                  // swc-expected-error {{sema_err_array_dim_zero}}

func bad(p: [0] s32) {}          // swc-expected-error {{sema_err_array_dim_zero}}
