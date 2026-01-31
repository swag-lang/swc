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

const PA = cast(const *Swag.TypeInfoStruct) #typeof(A)
#assert(PA.fields[0].name == "R")

#test
{
    var a: typeinfo = #typeof(f32)
    let b = a.flags | .Nullable
}

#test
{
    var a: typeinfo = #typeof(*f32)
    var b = cast(const *Swag.TypeInfoPointer)(a)
    var c = b.pointedType == f32
}

#test
{
    const a = #typeof(s32)
    const b = #typeof(s32)
    #assert(a == b)
    #assert(a == s32)
    #assert(s32 == a)

    const c: typeinfo = #typeof(s32)
    #assert(c == s32)

    // Compare two different typeinfos
    const e = #typeof(f32)
    #assert(a != e)
    #assert(e != s32)
}