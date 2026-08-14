#global private

// A register-sized struct rvalue as a UFCS receiver: the value comes back from the call
// in a register, and the pointer receiver needs a call-site home before its address can
// travel into the parameter. The scalar spill did not cover small aggregates, so the raw
// value bits were passed as the receiver pointer.
struct Id
{
    value: u64
}

impl Id
{
    #[Swag.NoInline]
    mtd const opEquals(other: Id)->bool
    {
        return .value == other.value
    }

    #[Swag.NoInline]
    mtd const sameAs(other: Id)->bool
    {
        return .value == other.value
    }

    #[Swag.NoInline]
    func make()->Id
    {
        var result: retval
        result.value = 42
        return result
    }
}

#test
{
    // Through the regular UFCS call path.
    var b: Id
    b.value = 42
    @assert(Id.make().sameAs(b))
}

#test
{
    // Through the explicit spec-op name.
    var b: Id
    b.value = 42
    @assert(Id.make().opEquals(b))
}

#test
{
    // Through the '==' operator.
    var b: Id
    b.value = 42
    @assert(Id.make() == b)
}
