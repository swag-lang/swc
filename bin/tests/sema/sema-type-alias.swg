#global internal

alias SSW = Swag

alias DWORD1 = u32
const A: DWORD1 = 0
#assert(#typeof(A) == u32)
#assert(#typeof(DWORD1) == u32)

#[Swag.Strict]
alias DWORD2 = u32
const A_DWORD2: DWORD2 = 5
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

var m: Meters
var s1: Seconds = m                 // swc-expected-error {{sema_err_cannot_cast}}
var s2: Seconds = cast(Seconds) m