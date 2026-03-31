#global fileprivate

struct BinaryIntBox
{
    value: u32
}

impl BinaryIntBox
{
    #[Swag.Overload]
    mtd const opBinary(other: const &BinaryIntBox)->BinaryIntBox
    {
        return {value: .value + other.value}
    }

    #[Swag.Overload]
    mtd const opBinary(other: u32)->BinaryIntBox
    {
        return {value: .value << other}
    }
}

struct MissingConstMe
{
    value: u64
}

impl MissingConstMe
{
    #[Swag.Overload]
    mtd opBinary(other: MissingConstMe)->MissingConstMe { return {}; } // swc-expected-error {{sema_err_spec_op_signature}}
}

struct MutatingOtherRef
{
    value: u64
}

impl MutatingOtherRef
{
    #[Swag.Overload]
    mtd const opBinary(other: &MutatingOtherRef)->MutatingOtherRef { return {}; } // swc-expected-error {{sema_err_spec_op_signature}}
}

struct MutatingOtherPtr
{
    value: u64
}

impl MutatingOtherPtr
{
    #[Swag.Overload]
    mtd const opBinary(other: *MutatingOtherPtr)->MutatingOtherPtr { return {}; } // swc-expected-error {{sema_err_spec_op_signature}}
}

struct(T) GenericMissingConstMe
{
    value: T
}

impl GenericMissingConstMe
{
    #[Swag.Overload]
    mtd(op: string) opBinary(other: const &GenericMissingConstMe'T)->GenericMissingConstMe'T { return {}; } // swc-expected-error {{sema_err_spec_op_signature}}
}

struct IndirectOtherByValue
{
    a: u64
    b: u64
}

impl IndirectOtherByValue
{
    #[Swag.Overload]
    mtd const opBinary(other: IndirectOtherByValue)->IndirectOtherByValue { return {}; } // swc-expected-error {{sema_err_spec_op_signature}}

    #[Swag.Overload]
    mtd const opBinary(other: const &IndirectOtherByValue)->IndirectOtherByValue
    {
        return {a: .a + other.a, b: .b + other.b}
    }
}

#test
{
    var lhs  = BinaryIntBox{value: 40}
    var rhs  = BinaryIntBox{value: 2}
    let sum  = lhs + rhs

    #assert(#typeof(sum) == BinaryIntBox)
    #assert(#typeof(sum.value) == u32)
}

#test
{
    var value = BinaryIntBox{value: 2}
    let shift = value << 4'u32

    #assert(#typeof(shift) == BinaryIntBox)
    #assert(#typeof(shift.value) == u32)
}

#test
{
    var lhs: GenericMissingConstMe'u32 = {value: 1}
    var rhs: GenericMissingConstMe'u32 = {value: 2}
    let result = lhs + rhs
    #assert(#typeof(result) == GenericMissingConstMe'u32)
}
