#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x = 456.0
    var v = @sqrt(@sqrt(x))
}
