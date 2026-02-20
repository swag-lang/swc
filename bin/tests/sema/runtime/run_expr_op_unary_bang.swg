#global internal

#test
{
    func unaryBangBool(a: bool)->bool { return !a }
    const V0 = #run unaryBangBool(true)
    const V1 = #run unaryBangBool(false)
    #assert(!V0)
    #assert(V1)
}

#test
{
    func unaryBangInt(a: s32)->bool { return !a }
    const V0 = #run unaryBangInt(0)
    const V1 = #run unaryBangInt(1)
    #assert(V0)
    #assert(!V1)
}

#test
{
    func unaryBangBad(a: [2] s32)->bool { return !a } // swc-expected-error {{sema_err_unary_operand_type}}
}
