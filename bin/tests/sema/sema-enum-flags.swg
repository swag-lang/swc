#global internal

enum AA { A, B }
const BB = AA.A | 1 // swc-expected-error {{sema_err_invalid_op_enum}}
const CC = 1 | AA.A // swc-expected-error {{sema_err_invalid_op_enum}}

#[Swag.EnumFlags]
enum DD: f32 { A, B, C } // swc-expected-error {{sema_err_invalid_enum_flags_type}}

#[Swag.EnumFlags]
{
    enum EE: u8 { A, B, C }
    enum FF: u16 { A, B, C }
    enum GG: u32 { A, B, C }
    enum HH: u64 { A, B, C }
}

#[Swag.EnumFlags]
enum II { A, B, C }
#assert(#typeof(II) == II)
#assert(#kindof(II) == u32)

#[Swag.EnumFlags]
enum JJ { A, B, C }
#assert(JJ.A == 1)
#assert(JJ.B == 2)
#assert(JJ.C == 4)

#[Swag.EnumFlags]
enum KK
{
    A = 0x80000000,
    B, // swc-expected-error {{sema_err_literal_overflow}}
}

#[Swag.EnumFlags]
enum LL : u64
{
    A = 0x80000000,
    B,
}
