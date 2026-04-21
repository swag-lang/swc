#global fileprivate

attr Foreign5(module: s32..., x: s32)   // swc-expected-error {{sema_err_variadic_not_last}}
attr VariadicNotLast1(a: s8..., b: s16)      // swc-expected-error {{sema_err_variadic_not_last}}
attr VariadicNotLast2(a: string..., b: s32)  // swc-expected-error {{sema_err_variadic_not_last}}
