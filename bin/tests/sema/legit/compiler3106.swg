#global fileprivate
#global skip
#test
{
    #[Swag.Inline]
    {
        func xx() => 666
    }

    @assert(xx() == 666)
}
