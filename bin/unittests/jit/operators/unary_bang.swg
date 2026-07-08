#global private

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

#test
{
    func unaryBangPointer(a: *void)->bool { return !a }
    const V0 = #run unaryBangPointer(null)
    const V1 = #run unaryBangPointer(cast(*void) 0x1000'u64)
    #assert(V0)
    #assert(!V1)
}

#test
{
    func unaryBangBang(a: s32)->bool { return !(!a) }
    const V0 = #run unaryBangBang(0)
    const V1 = #run unaryBangBang(12)
    #assert(!V0)
    #assert(V1)
}

// Truthiness of a value wrapped in an implicit bool cast must test the full value width.
// The implicit cast substitute is not visited by codegen: consumers read the operand payload,
// and the payload type must stay the value's real type (a pointer whose address has a zero low
// byte was wrongly seen as null when the compare width collapsed to 8 bits).
#test
{
    var buf: [512] u8
    var p: const [*] u8 = &buf[0]
    p = p + (256 - (cast(u64) p & 0xFF)) // force the address low byte to 0
    @assert((cast(u64) p & 0xFF) == 0)

    // through @dataof (the original @print swallowed-strings repro)
    let s = @mkstring(p, 1)
    if !@dataof(s) do
        @assert(false)

    // raw pointer under unary bang
    if !p do
        @assert(false)

    // raw pointer as a logical operand
    var ok = false
    if p and true do
        ok = true
    @assert(ok)

    // integer with a zero low byte (256) under unary bang, from a runtime source
    let x = cast(s64) ((cast(u64) p & 0xFF) + 256)
    if !x do
        @assert(false)
    if !(-x) do
        @assert(false)
}
