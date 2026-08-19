#global private

// '#simd' wraps a fixed-size array shape, nothing else.
var a: #simd u8             // swc-expected-error {{parser_err_simd_expected_array}}
