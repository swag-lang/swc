#global private

using Swag

// A '#[Swag.Tls]' global must be one copy per thread, starting from the declared value. Proving it
// needs a real OS thread: a value written on one thread must be invisible to the other, and each
// thread must see the initializer rather than whatever the previous one left behind.

#[Swag.Tls]
var g_Counter = 0'u64

#[Swag.Tls]
var g_Zero: u64

struct TlsPoint
{
    x: u64 = 11
    y: u64 = 22
}

#[Swag.Tls]
var g_Point: TlsPoint

#static if #os == Swag.TargetOs.Windows
{
    namespace Th
    {
        alias HANDLE                 = *void
        alias DWORD                  = u32
        alias SIZE_T                 = u64
        alias LPTHREAD_START_ROUTINE = func(*void)->DWORD

        const INFINITE = 0xFFFF_FFFF'u32

        #[Swag.Foreign("kernel32")]
        {
            func CreateThread(lpThreadAttributes: #null *void, dwStackSize: SIZE_T, lpStartAddress: LPTHREAD_START_ROUTINE, lpParameter: *void, dwCreationFlags: DWORD, lpThreadId: *DWORD)->HANDLE
            func WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD)->DWORD
            func CloseHandle(handle: HANDLE)
        }
    }

    struct TlsResult
    {
        seenCounter: u64
        seenZero:    u64
        seenPointX:  u64
        seenPointY:  u64
        ownCounter:  u64
    }

    func tlsWorker(param: *void)->Th.DWORD
    {
        let result = cast(*TlsResult) param

        // What the thread finds before writing anything is its own copy of the initializer, not
        // the value the main thread left in its copy.
        result.seenCounter = g_Counter
        result.seenZero    = g_Zero
        result.seenPointX  = g_Point.x
        result.seenPointY  = g_Point.y

        g_Counter  = 0xBBBB
        g_Zero     = 7
        g_Point.x  = 99
        result.ownCounter = g_Counter
        return 0
    }

    func runWorker(result: *TlsResult)
    {
        var tid: Th.DWORD
        let handle = Th.CreateThread(null, 0, &tlsWorker, result, 0, &tid)
        @assert(handle != null)
        discard Th.WaitForSingleObject(handle, Th.INFINITE)
        Th.CloseHandle(handle)
    }

    #test
    {
        // Compile-time execution has no thread-exit boundary of its own, so the per-thread copies
        // this proves belong to the produced program.
        if @jit() do
            return

        g_Counter = 0xAAAA
        g_Zero    = 3
        g_Point.x = 55

        var first: TlsResult
        runWorker(&first)

        @assert(first.seenCounter == 0)
        @assert(first.seenZero == 0)
        @assert(first.seenPointX == 11)
        @assert(first.seenPointY == 22)
        @assert(first.ownCounter == 0xBBBB)

        // The worker's writes stayed in the worker's copy.
        @assert(g_Counter == 0xAAAA)
        @assert(g_Zero == 3)
        @assert(g_Point.x == 55)
        @assert(g_Point.y == 22)

        // A second thread starts from the initializer as well, not from the first worker's values,
        // which is what a per-thread copy released at thread exit must give.
        var second: TlsResult
        runWorker(&second)
        @assert(second.seenCounter == 0)
        @assert(second.seenPointX == 11)
    }
}

// Taking the address of a thread-local global answers the calling thread's own copy, and reading
// through that pointer must agree with reading the name.
#test
{
    g_Counter = 0x1234

    let pointer = &g_Counter
    @assert(dref pointer == 0x1234)

    dref pointer = 0x5678
    @assert(g_Counter == 0x5678)

    g_Counter = 0
}
