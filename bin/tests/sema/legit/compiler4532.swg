#global fileprivate // swc-option sema-only
#global skip
//#global testerror

#[Swag.EnumFlags]
enum A
{
    R
}

#[Swag.Strict]
alias AL = A

//#[Swag.PrintBc]
#test
{
    var x: AL = R
    x |= .R
}
