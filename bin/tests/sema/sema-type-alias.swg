#global internal

alias SSW = Swag

alias DWORD1 = u32
const A: DWORD1 = 0
#assert(#typeof(A) == u32)
#assert(#typeof(DWORD1) == u32)

#[Swag.Strict]
alias DWORD2 = u32
const A_DWORD2: DWORD2 = cast(DWORD2) 5
const B_DWORD2: u32 = A_DWORD2 // swc-expected-error {{sema_err_cannot_cast}}
const C_DWORD2: u32 = cast(u32) A_DWORD2
#assert(C_DWORD2 == 5)

#[Swag.Strict]
alias SSW1 = Swag // swc-expected-error {{sema_err_not_type}}

#[Swag.Strict]
{
    alias Meters = s32
    alias Seconds = s32
}

const m: Meters = cast(Meters) 10
var s1: Seconds = m                 // swc-expected-error {{sema_err_cannot_cast}}
const s2: Seconds = cast(Seconds) m

var base_from_m: s32 = m               // swc-expected-error {{sema_err_cannot_cast}}
const base_from_m_ok: s32 = cast(s32) m

var m_from_base: Meters = cast(Meters) base_from_m_ok
var m_from_base_ok: Meters = cast(Meters) base_from_m_ok

// Seconds <-> base
var base_from_s: s32 = s2              // swc-expected-error {{sema_err_cannot_cast}}
const base_from_s_ok: s32 = cast(s32) s2

var s_from_base: Seconds = cast(Seconds) base_from_s_ok
var s_from_base_ok: Seconds = cast(Seconds) base_from_s_ok

// Cross strict aliases
var s3: Seconds = m                    // swc-expected-error {{sema_err_cannot_cast}}
var s4: Seconds = cast(Seconds) m

var m2: Meters = s2                    // swc-expected-error {{sema_err_cannot_cast}}
var m3: Meters = cast(Meters) s2