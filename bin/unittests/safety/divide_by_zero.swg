#global private
using Swag

#[Swag.NoInline]
func opaque(v: s32)->s32 => v

#[Swag.NoInline]
func opaqueU(v: u32)->u32 => v

// The guard reports, and the panic path never falls into the divide.
#[Swag.Safety(.Math, true)]
func signedDivide(value, divisor: s32)->s32
{
    return value / divisor     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run signedDivide(opaque(10), opaque(0))
}

// Unsigned goes through the same lowering now, and used to have no arm at all.
#[Swag.Safety(.Math, true)]
func unsignedDivide(value, divisor: u32)->u32
{
    return value / divisor     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run unsignedDivide(opaqueU(10), opaqueU(0))
}

#[Swag.Safety(.Math, true)]
func signedRemainder(value, divisor: s32)->s32
{
    return value % divisor     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run signedRemainder(opaque(10), opaque(0))
}

#[Swag.Safety(.Math, true)]
func compoundDivide(value, divisor: s32)->s32
{
    var result = value
    result /= divisor     // swc-expected-error {{safety_err_runtime}}
    return result
}

#test
{
    #run compoundDivide(opaque(10), opaque(0))
}

// Every ordinary division still computes the right answer, guard on and guard off.
#[Swag.Safety(.Math, true)]
func guardedResults()->bool
{
    var ok = true
    ok = ok and opaque(10) / opaque(3) == 3
    ok = ok and opaque(-10) / opaque(3) == -3
    ok = ok and opaque(10) % opaque(3) == 1
    ok = ok and opaque(-10) % opaque(3) == -1
    ok = ok and opaqueU(10) / opaqueU(3) == 3
    ok = ok and opaqueU(10) % opaqueU(3) == 1
    var acc = opaque(100)
    acc /= opaque(7)
    ok  = ok and acc == 14
    return ok
}

#[Swag.Safety(.Math, false)]
func unguardedResults()->bool
{
    var ok = true
    ok = ok and opaque(10) / opaque(3) == 3
    ok = ok and opaque(-10) % opaque(3) == -1
    ok = ok and opaqueU(10) / opaqueU(3) == 3
    return ok
}

#test
{
    Swag.assert(guardedResults())
    Swag.assert(unguardedResults())
}
