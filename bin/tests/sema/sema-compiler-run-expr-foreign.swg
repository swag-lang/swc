#global #if #os == Swag.TargetOs.Windows

#[Swag.Foreign("kernel32", "GetCurrentProcessId")]
func GetPidAlias()->u32;

#[Swag.Foreign("kernel32")]
{
    func GetCurrentProcessId()->u32;
}

#[Swag.PrintMicro]
#test
{
    const A = #run GetPidAlias()
    const B = #run GetCurrentProcessId()
    #assert(A != 0'u32)
    #assert(B != 0'u32)
    #assert(A == B)
}

#[Swag.Foreign("kernel32", "GetCurrentProcessId")]
func GetPidMissingArg(dummy: u32)->u32;

#[Swag.Foreign("kernel32", "lstrlenA")]
func LStrLenA(text: const *u8)->s32;

#[Swag.PrintMicro]
#test
{
    const A = #run GetPidAlias()
    const B = #run GetPidMissingArg(0'u32)
    #assert(A != 0'u32)
    #assert(B != 0'u32)
    #assert(A == B)
}

#[Swag.PrintMicro]
#test
{
    const L1 = #run LStrLenA(@dataof("A\0"))
    const L5 = #run LStrLenA(@dataof("ABCDE\0"))
    #assert(L1 == 1)
    #assert(L5 == 5)
}

#[Swag.Foreign("kernel32", "GetCurrentProcessId")]
func GetPidWithBody()->u32 // swc-expected-error {{sema_err_foreign_cannot_have_body}}
{
    return 0
}

#test { const X = #run GetPidMissingArg() } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const Y = #run GetPidMissingArg("bad") } // swc-expected-error {{sema_err_cannot_cast}}
