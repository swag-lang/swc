#global internal

enum A: u32 {}
enum A1 {}

enum A2
{
    A = 0,
    B,
    C = 5,
    D,
    E = 10,
}

var XX: s32
enum EA
{
    A = XX, // swc-expected-error {{sema_err_expr_not_const}}
}

enum EB: void {} // swc-expected-error {{sema_err_invalid_enum_type}}

enum EC: f32
{
    A // swc-expected-error {{sema_err_missing_enum_value}}
}

enum ED: s32
{
    A = 1.5 // swc-expected-error {{sema_err_cannot_cast}}
}

enum EE: s32
{
    A,
    A   // swc-expected-error {{sema_err_already_defined}}
}

// swc-expected-error@(+1,+2) {{sema_err_already_defined}}
enum EX: u32 {}
enum EX: f32 {}

