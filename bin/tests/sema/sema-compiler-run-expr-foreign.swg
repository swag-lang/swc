#global #if #os == Swag.TargetOs.Windows

#[Swag.Foreign("kernel32", "GetCurrentProcessId")]
func GetPidAlias()->u32;

#[Swag.Foreign("kernel32")]
{
    func GetCurrentProcessId()->u32;
}

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

#[Swag.Foreign("kernel32", "MulDiv")]
func MulDiv(number: s32, numerator: s32, denominator: s32)->s32;

#[Swag.Foreign("kernel32", "GetProcessHeap")]
func GetProcessHeap()->*void;

#[Swag.Foreign("kernel32", "HeapAlloc")]
func HeapAlloc(heap: *void, flags: u32, bytes: u64)->*void;

#[Swag.Foreign("kernel32", "HeapFree")]
func HeapFree(heap: *void, flags: u32, mem: *void)->bool;

#[Swag.Foreign("kernel32", "MultiByteToWideChar")]
func MultiByteToWideChar(codePage: u32, flags: u32, src: const *u8, srcCount: s32, dst: *u16, dstCount: s32)->s32;

#test
{
    const A = #run GetPidAlias()
    const B = #run GetPidMissingArg(0'u32)
    #assert(A != 0'u32)
    #assert(B != 0'u32)
    #assert(A == B)
}

#test
{
    const L1 = #run LStrLenA(@dataof("A"))
    const L5 = #run LStrLenA(@dataof("ABCDE"))
    #assert(L1 == 1)
    #assert(L5 == 5)
}

#test
{
    const A = #run MulDiv(21, 10, 5)
    const B = #run MulDiv(-30, 7, 3)
    #assert(A == 42)
    #assert(B == -70)
}

#test
{
    const H = #run GetProcessHeap()
    const P = #run HeapAlloc(H, 0'u32, 64'u64)
    const F = #run HeapFree(H, 0'u32, P)
    #assert(H != null)
    #assert(P != null)
    #assert(F)
}

#test
{
    const CP_UTF8 = 65001'u32
    #[Swag.PrintMicro("before-register-allocation")]
    const S1 = #run MultiByteToWideChar(CP_UTF8, 0'u32, @dataof("A"), 1, null, 0)
    const S5 = #run MultiByteToWideChar(CP_UTF8, 0'u32, @dataof("ABCDE"), 5, null, 0)
    #assert(S1 == 1)
    #assert(S5 == 5)
}

#test { const L = #run LStrLenA("ABCDE") } // swc-expected-error {{sema_err_cannot_cast}}
#test { const M = #run MulDiv(1, 2) } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const M = #run MulDiv(1, "x", 3) } // swc-expected-error {{sema_err_cannot_cast}}
#test { const A = #run HeapAlloc() } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const B = #run HeapAlloc(null, "x", 16'u64) } // swc-expected-error {{sema_err_cannot_cast}}
#test { const C = #run HeapFree(null, 0'u32) } // swc-expected-error {{sema_err_too_few_arguments}}

#[Swag.Foreign("kernel32", "GetCurrentProcessId")]
func GetPidWithBody()->u32 // swc-expected-error {{sema_err_foreign_cannot_have_body}}
{
    return 0
}

#test { const X = #run GetPidMissingArg() } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const Y = #run GetPidMissingArg("bad") } // swc-expected-error {{sema_err_cannot_cast}}
