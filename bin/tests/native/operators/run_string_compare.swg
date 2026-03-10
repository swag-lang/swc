// swc-option suite-test

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

#test
{
    let a = "a"
    let b = "b"
    let c = a < b // swc-expected-error {{sema_err_compare_operand_type}}
}
