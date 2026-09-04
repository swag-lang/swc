#global private

#assert(#nameof(#type func(s32)) == "func(s32)")
#assert(#nameof(#type func(s32, bool)) == "func(s32, bool)")
#assert(#nameof(#type func(s32, bool)->string) == "func(s32, bool)->string")
#assert(#nameof(#type func(s32, string)->*s32? fail ) == "func(s32, string)->*s32? fail")
#assert(#nameof(#type func||(s32)) == "func||(s32)")
#assert(#nameof(#type func||(s32, bool)) == "func||(s32, bool)")
#assert(#nameof(#type func||(s32, bool)->string) == "func||(s32, bool)->string")
#assert(#nameof(#type func||(s32, string)->*s32? fail ) == "func||(s32, string)->*s32? fail")

struct RecursiveFuncField
{
    cb: func(RecursiveFuncField)
}

struct RecursiveClosureField
{
    cb: func||(RecursiveClosureField)
}

struct(T) LambdaTypeBox
{
    value: T
}

#assert(#type LambdaTypeBox'func||(s32) == #type LambdaTypeBox'func||(s32))

#assert(#nameof(#type func()) == "func()")
#assert(#nameof(#type func(...)) == "func(...)")
#assert(#nameof(#type func(s32...)) == "func(s32...)")

#assert(#nameof(#type func(a: s32)) == "func(a: s32)")

func PtrMatch0() {}
func PtrMatch1(value: s32) {}
func PtrMatch2(lhs: s32, rhs: bool)->string => "ok"
func PtrMatch4(values: s32...)->s32
{
    var result = 0
    for value in values do
        result += value
    return result
}
func PtrMatch5(values: ...)->s32
{
    return cast(s32) values.count
}

func semaTest001()
{
    let p0: func()                  = &PtrMatch0
    let p1: func(value: s32)        = &PtrMatch1
    let p2: func(s32, bool)->string = &PtrMatch2
    let p4: func(s32...)->s32       = &PtrMatch4
    let p5: func(...)->s32          = &PtrMatch5

    p0()
    p1(10)

    let text = p2(1, true)
    #assert(#typeof(text) == string)

    let total = p4(1, 2, 3)
    #assert(#typeof(total) == s32)

    let count = p5(1, true, "ok")
    #assert(#typeof(count) == s32)
}
