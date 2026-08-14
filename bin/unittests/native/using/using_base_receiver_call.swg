#global private

// A method of an embedded 'using' base called through the derived value: the receiver
// pointer must reach the base subobject through the using path. The castless UFCS route
// only holds when the receiver IS the pointee; skipping the cast here once dereferenced
// the receiver value as the pointer.
struct(T) Box
{
    slot:  T
    count: u64
}

impl Box
{
    #[Swag.NoInline]
    mtd bump()
    {
        .count += 1
    }

    #[Swag.NoInline]
    mtd addValue(value: T)
    {
        .slot  = value
        .count += 1
    }

    #[Swag.NoInline]
    mtd addFwd(value: #fwd T)
    {
        .slot  = #fwd value
        .count += 1
    }
}

struct(T) BoxPtr
{
    using base: Box'(#null *T)
}

#test
{
    // Receiver only: no argument at all.
    var b: BoxPtr's32
    b.bump()
    @assert(b.count == 1)
}

#test
{
    // By-value argument.
    var i = 7's32
    var b: BoxPtr's32
    b.addValue(&i)
    @assert(b.count == 1)
    @assert(b.slot == &i)
}

#test
{
    // '#fwd' argument, including a typed null constant.
    var i = 7's32
    var b: BoxPtr's32
    b.addFwd(&i)
    @assert(b.count == 1)
    @assert(b.slot == &i)
    b.addFwd(cast(#null *s32) null)
    @assert(b.count == 2)
    @assert(b.slot == null)
}

#test
{
    // Control: the same calls on the base struct directly.
    var i = 7's32
    var b: Box'(#null *s32)
    b.bump()
    b.addValue(&i)
    b.addFwd(&i)
    @assert(b.count == 3)
    @assert(b.slot == &i)
}
