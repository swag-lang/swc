#global fileprivate

func(T, U) freeAccepts(first: T, second: U)->bool
{
    return #typeof(first) == T and #typeof(second) == U
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
    return #typeof(data.first) == bool and #typeof(data.second) == string and #typeof(data.third) == f32
}

func(A, B) localStructPartialTypeAnnotation()->bool
{
    struct(T, U = string, V = B) Local
    {
        first:  T
        second: U
        third:  V
    }

    var data: Local'A
    return #typeof(data.first) == A and #typeof(data.second) == string and #typeof(data.third) == B
}

struct SimpleMethodProbe
{
}

impl SimpleMethodProbe
{
    mtd(T, U) accepts(first: T, second: U)->bool
    {
        return #typeof(first) == T and #typeof(second) == U
    }
}

func semaTest001()
{
    var simple = SimpleMethodProbe{}

    #assert(#typeof(freeAccepts'(bool)(true, 0.0'f32)) == bool)
    #assert(#typeof(simple.accepts'(bool)(true, 0.0'f32)) == bool)
    #assert(#typeof(concreteLocalStructPartialTypeAnnotation()) == bool)
    #assert(#typeof(localStructPartialTypeAnnotation'(bool, f32)()) == bool)
}
