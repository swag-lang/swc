#global fileprivate // swc-option sema-only
#global skip
struct(T) AA
{
    field: T
}

func(T) RR()->AA
{
    return AA'T{}
}

#test
{
    var res = RR's32()
}
