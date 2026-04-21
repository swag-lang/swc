#global fileprivate

#[Swag.EnumFlags]
enum DD: f32 { A, B, C } // swc-expected-error {{sema_err_invalid_enum_flags_type}}

#[Swag.EnumFlags]
enum DD0: s8 { A, B, C } // swc-expected-error {{sema_err_invalid_enum_flags_type}}
