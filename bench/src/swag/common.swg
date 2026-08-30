// Shared prelude for the pure-Swag benchmarks.
// No dependency on any pre-compiled Swag module: only the default runtime allocator,
// compiler intrinsics, and the two kernel32 clock entry points used for timing.

struct BenchAllocationHeader
{
    totalSize: u64
    _padding:  u64
}

func benchAlloc(size: u64)->#null [*] void
{
    if size > Swag.U64.Max - #sizeof(BenchAllocationHeader) do
        return null

    var request: Swag.AllocatorRequest
    request.size      = size + #sizeof(BenchAllocationHeader)
    request.alignment = 16
    let allocator = Swag.getContext().allocator!
    allocator.alloc(&request)
    if !request.address do
        return null

    let header       = cast(*BenchAllocationHeader) request.address
    header.totalSize = request.size
    header._padding  = 0
    return cast([*] void) (cast([*] u8) header + #sizeof(BenchAllocationHeader))
}

func benchFree(ptr: #null [*] void)
{
    if !ptr do
        return

    let header = cast(*BenchAllocationHeader) (cast([*] u8) ptr! - #sizeof(BenchAllocationHeader))
    var request: Swag.AllocatorRequest
    request.address = header
    request.size    = header.totalSize
    let allocator   = Swag.getContext().allocator!
    allocator.free(&request)
}

#[Swag.Foreign("kernel32", "QueryPerformanceCounter")]
func qpc(v: *u64)->s32

#[Swag.Foreign("kernel32", "QueryPerformanceFrequency")]
func qpf(v: *u64)->s32

func now()->f64
{
    var c: u64
    var f: u64
    discard qpc(&c)
    discard qpf(&f)
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
