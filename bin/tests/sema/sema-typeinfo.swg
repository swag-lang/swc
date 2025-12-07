#assert(s32 == s32)
#assert(s32 != u32)
#assert(!(s8 == s32))
#assert(s32 == bool) // swc-expected-error {{sema_err_compiler_assert}}