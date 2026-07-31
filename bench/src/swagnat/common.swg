// Shared prelude for the pure-Swag benchmarks.
// No dependency on any pre-compiled Swag module: only compiler intrinsics and
// the two kernel32 clock entry points every runtime here uses for timing.

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
    @print("CHECK=", check, " MS=", (t1 - t0) * 1000.0'f64, "\n")
}
