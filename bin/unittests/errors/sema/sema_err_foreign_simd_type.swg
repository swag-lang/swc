#global private

// A C-convention foreign boundary has no rule for simd values; only the Swag
// calling convention carries them.
#[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
func badParam(v: #simd [4] s32);            // swc-expected-error {{sema_err_foreign_simd_type}}

#[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
func badReturn()->#simd [4] f32;            // swc-expected-error {{sema_err_foreign_simd_type}}

#[Swag.Foreign("kernel32", callconv: Swag.CallConv.WindowsX64)]
func badExplicit(v: #simd [16] u8);         // swc-expected-error {{sema_err_foreign_simd_type}}
