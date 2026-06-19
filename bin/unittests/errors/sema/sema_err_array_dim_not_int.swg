#global fileprivate

// Array dimensions must be integer; floats and other non-integer types are rejected.
var a: [2.0] s32                 // swc-expected-error {{sema_err_array_dim_not_int}}
var b: [3.5'f32] bool            // swc-expected-error {{sema_err_array_dim_not_int}}
var c: [true] s32                // swc-expected-error {{sema_err_array_dim_not_int}}
