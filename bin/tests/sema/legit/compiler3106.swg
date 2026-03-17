#global fileprivate // swc-option sema-only
#global skip
#test
{
    #[Swag.Inline]
    {
        func xx() => 666
    }

    @assert(xx() == 666)
}
