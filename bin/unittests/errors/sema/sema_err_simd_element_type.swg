#global private

// A '#simd' vector only accepts sized native numeric lanes.
var a: #simd [16] bool      // swc-expected-error {{sema_err_simd_element_type}}
var b: #simd [2] string     // swc-expected-error {{sema_err_simd_element_type}}
var c: #simd [4] *u32       // swc-expected-error {{sema_err_simd_element_type}}
var d: #simd [4] rune       // swc-expected-error {{sema_err_simd_element_type}}
