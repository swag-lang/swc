#global fileprivate

// 'var T: <type>' declares a type parameter so it cannot carry a value type annotation.
struct(var T : s32) A {}                  // swc-expected-error {{parser_err_gen_param_type}}
struct(var U : bool) B {}                 // swc-expected-error {{parser_err_gen_param_type}}
func(var X : s64) foo() {}                // swc-expected-error {{parser_err_gen_param_type}}
