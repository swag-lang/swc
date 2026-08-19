#global private

// A '#simd' vector is one dimension of exactly 16 bytes.
var a: #simd [3] s32        // swc-expected-error {{sema_err_simd_shape}}
var b: #simd [16] u16       // swc-expected-error {{sema_err_simd_shape}}
var c: #simd [2] f32        // swc-expected-error {{sema_err_simd_shape}}
var d: #simd [2, 2] s32     // swc-expected-error {{sema_err_simd_shape}}
var e: #simd [..] u8        // swc-expected-error {{sema_err_simd_shape}}
var f: #simd [?] u8         // swc-expected-error {{sema_err_simd_shape}}
