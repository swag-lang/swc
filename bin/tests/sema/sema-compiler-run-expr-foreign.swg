#global #if #os == Swag.TargetOs.Windows

#[Swag.Foreign("kernel32", "GetCurrentProcessId")]
func GetPidAlias()->u32;

#[Swag.Foreign("kernel32", "GetCurrentProcess")]
func GetCurrentProcess()->*void;

#[Swag.Foreign("kernel32", "GetProcessId")]
func GetProcessId(process: *void)->u32;

#[Swag.Foreign("kernel32", "VirtualAlloc")]
func VirtualAlloc(address: *void, bytes: u64, allocType: u32, protect: u32)->*void;

#[Swag.Foreign("kernel32", "VirtualFree")]
func VirtualFree(address: *void, bytes: u64, freeType: u32)->bool;

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

#test
{
    const H = #run GetCurrentProcess()
    const A = #run GetPidAlias()
    const B = #run GetProcessId(null)
    #assert(H != null)
    #assert(A != 0'u32)
    #assert(B == 0'u32)
}

// #test
// {
//     const MEM_COMMIT  = 0x1000'u32
//     const MEM_RESERVE = 0x2000'u32
//     const MEM_RELEASE = 0x8000'u32
//     const PAGE_READWRITE = 0x04'u32
//     const P = #run VirtualAlloc(null, 4096'u64, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)
//     const F = #run VirtualFree(P, 0'u64, MEM_RELEASE)
//     #assert(P != null)
//     #assert(F)
// }

#test
{
    const MEM_RELEASE = 0x8000'u32
    const F = #run VirtualFree(null, 0'u64, MEM_RELEASE)
    #assert(!F)
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
    const S1 = #run MultiByteToWideChar(CP_UTF8, 0'u32, @dataof("A"), 1, null, 0)
    const S5 = #run MultiByteToWideChar(CP_UTF8, 0'u32, @dataof("ABCDE"), 5, null, 0)
    #assert(S1 == 1)
    #assert(S5 == 5)
}

#test
{
    const Z = #run LStrLenA(@dataof(""))
    const L10 = #run LStrLenA(@dataof("0123456789"))
    #assert(Z == 0)
    #assert(L10 == 10)
}

#test
{
    const A = #run MulDiv(7, -6, 3)
    const B = #run MulDiv(-8, -9, 6)
    #assert(A == -14)
    #assert(B == 12)
}

#test
{
    const H = #run GetProcessHeap()
    const P1 = #run HeapAlloc(H, 0'u32, 1'u64)
    const P2 = #run HeapAlloc(H, 0'u32, 128'u64)
    const F1 = #run HeapFree(H, 0'u32, P1)
    const F2 = #run HeapFree(H, 0'u32, P2)
    #assert(H != null)
    #assert(P1 != null)
    #assert(P2 != null)
    #assert(F1)
    #assert(F2)
}

#test
{
    const CP_UTF8 = 65001'u32
    const S2 = #run MultiByteToWideChar(CP_UTF8, 0'u32, @dataof("AB"), 2, null, 0)
    const S8 = #run MultiByteToWideChar(CP_UTF8, 0'u32, @dataof("ABCDEFGH"), 8, null, 0)
    #assert(S2 == 2)
    #assert(S8 == 8)
}

#test { const L = #run LStrLenA("ABCDE") } // swc-expected-error {{sema_err_cannot_cast}}
#test { const L = #run LStrLenA(@dataof("ABCDE"), 5) } // swc-expected-error {{sema_err_too_many_arguments}}
#test { const M = #run MulDiv(1, 2) } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const M = #run MulDiv(1, "x", 3) } // swc-expected-error {{sema_err_cannot_cast}}
#test { const M = #run MulDiv(1, 2, 3, 4) } // swc-expected-error {{sema_err_too_many_arguments}}
#test { const M = #run MulDiv(6, 2'u32, 3); #assert(M == 4) }
#test { const A = #run HeapAlloc() } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const B = #run HeapAlloc(null, "x", 16'u64) } // swc-expected-error {{sema_err_cannot_cast}}
#test { const C = #run HeapAlloc(null, 0'u32, 16'u64, 1) } // swc-expected-error {{sema_err_too_many_arguments}}
#test { const C = #run HeapFree(null, 0'u32) } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const D = #run HeapFree(null, 0'u32, null, 1) } // swc-expected-error {{sema_err_too_many_arguments}}
#test { const E = #run HeapFree(null, "bad", null) } // swc-expected-error {{sema_err_cannot_cast}}
#test { const X = #run GetPidMissingArg() } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const Y = #run GetPidMissingArg("bad") } // swc-expected-error {{sema_err_cannot_cast}}
#test { const Z = #run GetPidAlias(1) } // swc-expected-error {{sema_err_too_many_arguments}}
#test { const W = #run MultiByteToWideChar(65001'u32, 0'u32, @dataof("A"), 1, null) } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const V = #run MultiByteToWideChar(65001'u32, 0'u32, @dataof("A"), "bad", null, 0) } // swc-expected-error {{sema_err_cannot_cast}}
#test { const P = #run GetProcessId() } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const P = #run GetProcessId("bad") } // swc-expected-error {{sema_err_cannot_cast}}
#test { const V = #run VirtualAlloc() } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const V = #run VirtualAlloc(null, 4096'u64, 0x1000'u32, 0x04'u32, 1) } // swc-expected-error {{sema_err_too_many_arguments}}
#test { const V = #run VirtualAlloc("bad", 4096'u64, 0x1000'u32, 0x04'u32) } // swc-expected-error {{sema_err_cannot_cast}}
#test { const V = #run VirtualFree() } // swc-expected-error {{sema_err_too_few_arguments}}
#test { const V = #run VirtualFree(null, 0'u64, 0x8000'u32, 1) } // swc-expected-error {{sema_err_too_many_arguments}}
#test { const V = #run VirtualFree("bad", 0'u64, 0x8000'u32) } // swc-expected-error {{sema_err_cannot_cast}}

#[Swag.Foreign("kernel32", "GetCurrentProcessId")]
func GetPidWithBody()->u32 { return 0; } // swc-expected-error {{sema_err_foreign_cannot_have_body}}
