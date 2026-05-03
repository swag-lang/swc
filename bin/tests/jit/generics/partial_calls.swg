#global fileprivate

func(T, U) freeAccepts(first: T, second: U)->bool
{
    return #typeof(first) == T and #typeof(second) == U and first == true and second == 0.0'f32
}

func concreteLocalStructPartialTypeAnnotation()->bool
{
    struct(T, U = string, V = f32) Local
    {
        first:  T
        second: U
        third:  V
    }

    var data: Local'bool
    data.first = true
    data.second = "ok"
    data.third = 3.5
    return #typeof(data.first) == bool and #typeof(data.second) == string and #typeof(data.third) == f32 and data.first and data.second == "ok" and data.third == 3.5'f32
}

func(A, B) localStructPartialTypeAnnotation(value: A, tail: B)->bool
{
    struct(T, U = string, V = B) Local
    {
        first:  T
        second: U
        third:  V
    }

    var data: Local'A
    data.first = value
    data.second = "ok"
    data.third = tail
    return #typeof(data.first) == A and #typeof(data.second) == string and #typeof(data.third) == B and data.first == value and data.second == "ok" and data.third == tail
}

struct SimpleMethodProbe
{
}

impl SimpleMethodProbe
{
    mtd(T, U) accepts(first: T, second: U)->bool
    {
        return #typeof(first) == T and #typeof(second) == U and first == true and second == 0.0'f32
    }
}

#test
{
    var simple = SimpleMethodProbe{}
    let freeOk = freeAccepts'(bool)(true, 0.0'f32)
    let methodOk = simple.accepts'(bool)(true, 0.0'f32)

    #assert(#typeof(freeOk) == bool)
    #assert(#typeof(methodOk) == bool)
    @assert(freeOk)
    @assert(methodOk)
}

#test
{
    let concrete = concreteLocalStructPartialTypeAnnotation()
    let local = localStructPartialTypeAnnotation'(bool, f32)(true, 1.5)

    #assert(#typeof(concrete) == bool)
    #assert(#typeof(local) == bool)
    @assert(concrete)
    @assert(local)
}
