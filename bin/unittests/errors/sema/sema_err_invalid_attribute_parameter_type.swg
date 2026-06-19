#global fileprivate

attr Foreign2(module: any)              // swc-expected-error {{sema_err_invalid_attribute_parameter_type}}
attr Foreign4(module: ..., x: s32)      // swc-expected-error {{sema_err_invalid_attribute_parameter_type}}
