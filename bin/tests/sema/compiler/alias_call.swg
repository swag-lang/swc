#global fileprivate

#[Swag.Macro]
func macroPair(value: s32, stmt: #code void)
{
    let #alias0 = value
    let #alias1 = value * 2
    #inject(stmt)
}

#[Swag.Mixin]
func declarePair(value: s32)
{
    const #alias0: s32 = value
    const #alias1: s32 = value + 1
}

#test
{
    macroPair(|first| 21)
    {
        @assert(first == 21)
        @assert(#alias1 == 42)
    }
}

#test
{
    macroPair(|left, right| 12)
    {
        @assert(left == 12)
        @assert(right == 24)
    }
}

#test
{
    declarePair(|named| 10)
    @assert(named == 10)
    @assert(#alias1 == 11)
}

#test
{
    declarePair(|lhs, rhs| 20)
    @assert(lhs == 20)
    @assert(rhs == 21)
}

#test
{
    declarePair(30)
    @assert(#alias0 == 30)
    @assert(#alias1 == 31)
}
