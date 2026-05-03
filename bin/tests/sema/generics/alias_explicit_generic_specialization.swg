#global fileprivate

func(T, U) freeAccepts(first: T, second: U)->bool
{
    return #typeof(first) == T and #typeof(second) == U
}

struct(T) Box
{
    value: T
}

alias GenericFreeAlias = freeAccepts
alias GenericBoxAlias  = Box

func semaTest001()
{
    #assert(#typeof(GenericFreeAlias'(bool)(true, 0.0'f32)) == bool)

    let boxed: GenericBoxAlias'bool
    #assert(#typeof(boxed.value) == bool)
}
