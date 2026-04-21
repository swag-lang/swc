#global fileprivate

attr Default1(x: s32 = 0, y: s32)       // swc-expected-error {{sema_err_parameter_default_value_not_last}}
attr DefaultBadInt8(a: s8 = 0, b: s16)           // swc-expected-error {{sema_err_parameter_default_value_not_last}}
attr DefaultBadString(a: string = "", b: rune)   // swc-expected-error {{sema_err_parameter_default_value_not_last}}
