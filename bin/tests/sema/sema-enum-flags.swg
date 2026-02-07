#global internal

enum AA { A, B }
const BB = AA.A | 1 // swc-expected-error {{sema_err_invalid_op_enum}}
const CC = 1 | AA.A // swc-expected-error {{sema_err_invalid_op_enum}}

#[Swag.EnumFlags]
enum DD: f32 { A, B, C } // swc-expected-error {{sema_err_invalid_enum_flags_type}}

#[Swag.EnumFlags]
enum DD0: s8 { A, B, C } // swc-expected-error {{sema_err_invalid_enum_flags_type}}

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
enum KK : u32
{
    A = 0x80000000,
    B, // swc-expected-error {{sema_err_literal_overflow}}
}

#[Swag.EnumFlags]
enum MM : u32
{
    A = 5,
    B // swc-expected-error {{sema_err_flag_enum_power_2}}
}

#[Swag.EnumFlags]
enum LL : u64
{
    A = 0x80000000,
    B,
}

#[Swag.EnumFlags]
enum NN : u64
{
    A = 0,
    B,
}
#assert(NN.A == 0)
#assert(NN.B == 1)

#[Swag.EnumFlags]
enum OO : u8 { A, B, C }
#assert(#kindof(OO) == u8)

#[Swag.EnumFlags]
enum PP : u16 { A, B, C }
#assert(#kindof(PP) == u16)

#[Swag.EnumFlags]
enum QQ : u64 { A, B, C }
#assert(#kindof(QQ) == u64)

#[Swag.EnumFlags]
enum RR : u8
{
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
}
#assert(RR.A == 1)
#assert(RR.B == 2)
#assert(RR.C == 4)
#assert(RR.D == 8)
#assert(RR.E == 16)
#assert(RR.F == 32)
#assert(RR.G == 64)
#assert(RR.H == 0x80)

#[Swag.EnumFlags]
enum SS : u8
{
    A = 0x80,
    B, // swc-expected-error {{sema_err_literal_overflow}}
}

#[Swag.EnumFlags]
enum SS0 : u16
{
    A = 0x8000,
    B, // swc-expected-error {{sema_err_literal_overflow}}
}

#[Swag.EnumFlags]
enum SS1 : u32
{
    A = 0x8000_0000,
    B, // swc-expected-error {{sema_err_literal_overflow}}
}

#[Swag.EnumFlags]
enum SS2 : u64
{
    A = 0x8000000000000000,
    B, // swc-expected-error {{sema_err_literal_overflow}}
}

#assert((JJ.A | JJ.B) == 3)
#assert((JJ.A | JJ.C) == 5)
#assert((JJ.A | JJ.B | JJ.C) == 7)
#assert((JJ.A & JJ.B) == 0)
#assert(((JJ.A | JJ.B) & JJ.B) == JJ.B)

#assert((JJ.A & JJ.A) == JJ.A)
#assert((JJ.A & JJ.B) == 0)
#assert(((JJ.A | JJ.B) & JJ.B) == JJ.B)
#assert(((JJ.A | JJ.B | JJ.C) & JJ.C) == JJ.C)

#assert((NN.A & NN.B) == 0)
#assert((NN.B & NN.B) == NN.B)

const AND1 = JJ.A & 1
const AND2 = 1 & JJ.A

#assert((JJ.A ^ JJ.B) == 3)              // 1 ^ 2 = 3
#assert(((JJ.A | JJ.B) ^ JJ.B) == JJ.A)  // toggle off
#assert(((JJ.A | JJ.B | JJ.C) ^ JJ.B) == (JJ.A | JJ.C))
#assert((JJ.A ^ JJ.A) == 0)              // XOR cancels identical flag

#assert((NN.A ^ NN.B) == 1)
#assert((NN.B ^ NN.B) == 0)

const XOR1 = JJ.A ^ 1
const XOR2 = 1 ^ JJ.A

const AA1 = ~JJ.A
const AA2 = JJ.B & ~JJ.A
