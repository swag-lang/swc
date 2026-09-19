// Shared prelude for the pure-Swag benchmarks.
// Uses the default runtime allocator and compiler intrinsics; timing consumes the official
// Win32 bindings without depending on the portable standard-library implementations.

struct BenchAllocationHeader
{
    totalSize: u64
    _padding:  u64
}

func benchAlloc(size: u64)->[*] void?
{
    if size > Swag.U64.Max - #sizeof(BenchAllocationHeader) do
        return null

    var request: Swag.AllocatorRequest
    request.size      = size + #sizeof(BenchAllocationHeader)
    request.alignment = 16
    let allocator = Swag.getContext().allocator!
    allocator.alloc(&request)
    if not request.address do
        return null

    let header = cast(*BenchAllocationHeader) request.address
    header.totalSize = request.size
    header._padding  = 0
    return cast([*] void) (cast([*] u8) header + #sizeof(BenchAllocationHeader))
}

func benchFree(ptr: [*] void?)
{
    if not ptr do
        return

    let header = cast(*BenchAllocationHeader) (cast([*] u8) ptr - #sizeof(BenchAllocationHeader))
    var request: Swag.AllocatorRequest
    request.address = header
    request.size    = header.totalSize
    let allocator = Swag.getContext().allocator!
    allocator.free(&request)
}

func now()->f64
{
    var c, f: Win32.LARGE_INTEGER
    Win32.QueryPerformanceCounter(&c)
    Win32.QueryPerformanceFrequency(&f)
    return cast(f64) c / cast(f64) f
}

var g_Seed = 12345'u64

func rnd()->u64
{
    g_Seed = (g_Seed * 16807) % 2147483647
    return g_Seed
}

func report(check: u64, t0, t1: f64)
{
    Swag.print("CHECK=", check, " MS=", (t1 - t0) * 1000.0'f64, "\n")
}
