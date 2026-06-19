#global fileprivate

// Empty '[]' in a type position requires an explicit specifier ('*', '..', '?') or a dimension.
enum A: [] s32 { Z }                     // swc-expected-error {{parser_err_expected_array_dim}}
var globalArr: [] s32                    // swc-expected-error {{parser_err_expected_array_dim}}
