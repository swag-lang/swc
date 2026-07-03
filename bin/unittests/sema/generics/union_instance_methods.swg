#global private

union(T) ValueOrPtr
{
    value: T
    ptr:   *T
}

impl ValueOrPtr
{
    mtd sameType(other: T)->bool
    {
        return #typeof(other) == T
    }

    mtd(U) pair(other: U)->bool
    {
        return #typeof(.value) == T and #typeof(other) == U
    }
}

func semaTest001()
{
    var boxed = ValueOrPtr's32{value: 10}
    @assert(boxed.sameType(12))
    @assert(boxed.pair'bool(true))
}
