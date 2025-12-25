#global internal

var XX: s32
enum A
{
    A = XX, // swc-expected-error {{sema_err_expr_not_const}}
}

enum B: void {} // swc-expected-error {{sema_err_invalid_enum_type}}

enum C: f32
{
    A // swc-expected-error {{sema_err_missing_enum_value}}
}

enum D: s32
{
    A = 1.5 // swc-expected-error {{sema_err_cannot_cast}}
}

enum E: s32
{
    A,
    A   // swc-expected-error {{sema_err_already_defined}}
}

// swc-expected-error@(+1,+2) {{sema_err_already_defined}}
enum F: u32 { A }
enum F: f32 { A = 0 }

enum G: s8
{
    A = 128 // swc-expected-error {{sema_err_literal_overflow}}
}

enum H: u8
{
    A = 255,
    B  // swc-expected-error {{sema_err_literal_overflow}}
}

enum I: u8 {} // swc-expected-error {{sema_err_empty_enum}}

enum J: any {} // swc-expected-error {{sema_err_invalid_enum_type}}
enum K: cstring {} // swc-expected-error {{sema_err_invalid_enum_type}}