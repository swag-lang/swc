#global private

// Filling every lane with one value copies it; 'Swag.vecsplat' is that operation, and a cast
// from a scalar names a conversion that does not happen.
const A = cast(#simd [4] s32) 5's32       // swc-expected-error {{sema_err_simd_scalar_cast}}
const B = cast(#simd [16] u8) 200'u8      // swc-expected-error {{sema_err_simd_scalar_cast}}
const C = cast(#simd [2] f64) 1.5'f64     // swc-expected-error {{sema_err_simd_scalar_cast}}

// The lane type of the scalar does not change the answer.
const D = cast(#simd [4] s32) 5's16     // swc-expected-error {{sema_err_simd_scalar_cast}}
