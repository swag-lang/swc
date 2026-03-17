#global fileprivate // swc-option sema-only
#global skip
public func append2430(buf: #null *void, fmt: string, values: ...)
    verify
    {
        if !#isconstexpr(fmt) do
            return true
        return true
    }
{
}

#test
{
    append2430(null, "toto")
}
