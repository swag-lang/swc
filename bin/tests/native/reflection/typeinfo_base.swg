#global fileprivate // 

#assert(s32 == s32)
#assert(s32 != u32)
#assert(!(s8 == s32))

#assert((cast(const *Swag.TypeInfo) #typeof(f32)).name == "f32")
#assert((cast(typeinfo) #typeof(f32)).name == "f32")

#assert((cast(const *Swag.TypeInfoPointer) #typeof(*f32)).pointedType.name == "f32")

struct A { R, G, B: s32 }
#assert(@countof((cast(const *Swag.TypeInfoStruct) #typeof(A)).fields) == 3)

#test
{
    using Swag

    let nativeInfo = bool
    let arrayInfo = #type [2] s32
    let literalArrayInfo = #typeof([1, 2, 3])

    #assert(#typeof(nativeInfo) == #typeof(const *TypeInfoNative))
    #assert(#typeof(arrayInfo) == #typeof(const *TypeInfoArray))
    #assert(#typeof(literalArrayInfo) == #typeof(const *TypeInfoArray))
    #assert(literalArrayInfo.kind == TypeInfoKind.Array)
    #assert(#typeof({1, 2, 3}).kind == TypeInfoKind.Struct)
}

#[Swag.ConstExpr]
func getDeclaredType(useString: bool)->typeinfo
{
    if useString do
        return string
    else do
        return s32
}

#test
{
    const type0 = getDeclaredType(useString: false)
    const type1 = getDeclaredType(useString: true)
    var x: #decltype(type0)
    var y: #decltype(type1)
    #assert(#typeof(x) == s32)
    #assert(#typeof(y) == string)
    @assert(x == 0)
    y = "hello"
    @assert(y == "hello")
}

const PA = cast(const *Swag.TypeInfoStruct) #typeof(A)
#assert(PA.fields[0].name == "R")
#assert(PA.fields[1].name == "G")
#assert(PA.fields[2].name == "B")
#assert(PA.fields[2].pointedType == s32)
#assert(PA.fields[0].offset == 0)
#assert(PA.fields[1].offset == 4)
#assert(PA.fields[2].offset == 8)




#test
{
    const a = #typeof(s32)
    const b = #typeof(s32)
    #assert(a == b)
    #assert(a == s32)
    #assert(s32 == a)

    const c: typeinfo = #typeof(s32)
    #assert(c == s32)

    const e: typeinfo = #typeof(f32)
    #assert(a != e)
    #assert(e != s32)
    @assert(a == b)
    @assert(a == s32)
    @assert(a != e)
}

#test
{
    const p = #typeof(*s32)
    #assert((cast(const *Swag.TypeInfoPointer) p).pointedType == s32)
    @assert((cast(const *Swag.TypeInfoPointer) p).pointedType == s32)
}

#test
{
    var hit = false
    switch PA.fields[2].pointedType
    {
        case s32:
            hit = true
            break
        default:
            hit = false
            break
    }

    @assert(hit)
}

#test
{
    const t = #typeof(A)
    #assert((cast(const *Swag.TypeInfo) t).name == "A")
    @assert((cast(const *Swag.TypeInfo) t).name == "A")
}
