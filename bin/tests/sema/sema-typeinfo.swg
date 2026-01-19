#assert(s32 == s32)
#assert(s32 != u32)
#assert(!(s8 == s32))
#assert(s32 == bool) // swc-expected-error {{sema_err_compiler_assert}}

#assert((cast(const *Swag.TypeInfo) f32).name == "f32")
#assert((cast(typeinfo) f32).name == "f32")

#assert((cast(const *Swag.TypeInfoPointer) *f32).pointedType.name == "f32")