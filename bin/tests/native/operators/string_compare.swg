// 

#global fileprivate

func stringEq(a: string, b: string)->bool
{
    return a == b
}

func stringNe(a: string, b: string)->bool
{
    return a != b
}

#test
{
    @assert(stringEq("toto", "toto"))
    @assert(!stringEq("toto", "titi"))
    @assert(stringNe("toto", "titi"))
    @assert(!stringNe("toto", "toto"))
}

