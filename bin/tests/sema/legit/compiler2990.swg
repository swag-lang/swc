#global fileprivate // swc-option sema-only
#global skip
struct(T) AA
{
    value: T
}

func A()
{
    var x: AA'{ a: s32 }
    x.value.a = 0
}

func B()
{
    var x: AA'{ b: s32 }
    x.value.b = 0
}
