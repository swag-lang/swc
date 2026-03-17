#global fileprivate // swc-option sema-only
#global skip
#test
{
    {
        alias point = string
        func toto(x: point)
        {
            var y: point
        }

        toto("string")
    }
}
