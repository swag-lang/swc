#global fileprivate

alias SSW = Swag

alias DWORD1 = u32
const A: DWORD1 = 0
#assert(#typeof(A) == u32)
#assert(#typeof(DWORD1) == u32)

#[Swag.Strict]
alias DWORD2 = u32
const A_DWORD2: DWORD2 = cast(DWORD2) 5
const C_DWORD2: u32 = cast(u32) A_DWORD2
#assert(C_DWORD2 == 5)

#[Swag.Strict]
{
    alias Meters = s32
    alias Seconds = s32
}

const m: Meters = cast(Meters) 10
const s2: Seconds = cast(Seconds) m

const base_from_m_ok: s32 = cast(s32) m

var m_from_base: Meters = cast(Meters) base_from_m_ok
var m_from_base_ok: Meters = cast(Meters) base_from_m_ok

const base_from_s_ok: s32 = cast(s32) s2

var s_from_base: Seconds = cast(Seconds) base_from_s_ok
var s_from_base_ok: Seconds = cast(Seconds) base_from_s_ok

var s4: Seconds = cast(Seconds) m

var m3: Meters = cast(Meters) s2
