#global private

union(T) ValueOrPtr
{
    value: T
    ptr:   *T
}

impl ValueOrPtr
{
    func makeValue(value: T)->ValueOrPtr'T
    {
        return {value: value}
    }
}

alias ValueOrPtrAlias  = ValueOrPtr
alias ValueOrPtrAlias2 = ValueOrPtrAlias

func semaTest001()
{
    let boxed1 = ValueOrPtr's32.makeValue(42)
    let boxed2 = ValueOrPtrAlias2's32.makeValue(24)

    #assert(#typeof(boxed1.value) == s32)
    #assert(#typeof(boxed2.value) == s32)
}
