#global fileprivate // swc-option sema-only
#global skip
alias A = u8

#test
{
    var x: [..] A
    let y  = cast(string) x
}
