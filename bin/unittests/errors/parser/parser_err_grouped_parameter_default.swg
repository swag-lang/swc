#global private

func typed(left, right: s32 = 0) {} // swc-expected-error {{parser_err_grouped_parameter_default}}
func inferred(left, right = 0) {}   // swc-expected-error {{parser_err_grouped_parameter_default}}

attr GroupedDefaults(left, right: s32 = 0) // swc-expected-error {{parser_err_grouped_parameter_default}}
