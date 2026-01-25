#global internal

#assert(s32 == s32)
#assert(s32 != u32)
#assert(!(s8 == s32))
#assert(s32 == bool) // swc-expected-error {{sema_err_compiler_assert}}

#assert((cast(const *Swag.TypeInfo) #typeof(f32)).name == "f32")
#assert((cast(typeinfo) #typeof(f32)).name == "f32")

#assert((cast(const *Swag.TypeInfoPointer) #typeof(*f32)).pointedType.name == "f32")

struct A { R, G, B: s32 }
#assert(@countof((cast(const *Swag.TypeInfoStruct) #typeof(A)).fields) == 3)

#test
{
    var a: typeinfo = #typeof(f32)
    let b = a.flags | .Nullable
}