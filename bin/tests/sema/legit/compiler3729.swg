#global fileprivate // swc-option sema-only
#global skip
#test
{
    let md = @modules
    foreach t in md[0].types
    {
        var x = t.fullname
    }
}
