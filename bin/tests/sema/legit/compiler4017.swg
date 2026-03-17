#global fileprivate // swc-option sema-only
#global skip
#global #[Swag.Safety(.All, .Overflow, true)]
//#global testerror

#test
{
    var x = 1
    x <<= 32
    x <<= 32
}
