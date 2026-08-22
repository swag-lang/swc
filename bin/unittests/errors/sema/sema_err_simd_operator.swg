#global private

// Operators the lanes cannot provide are rejected, not synthesized.
func divInts(a, b: #simd [4] s32)
{
    let c = a / b     // swc-expected-error {{sema_err_simd_operator}}
}

func modInts(a, b: #simd [4] s32)
{
    let c = a % b     // swc-expected-error {{sema_err_simd_operator}}
}
