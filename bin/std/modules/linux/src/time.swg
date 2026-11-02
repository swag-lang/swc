#global if #os == Swag.TargetOs.Linux
#global export

const CLOCK_REALTIME  = 0's32
const CLOCK_MONOTONIC = 1's32

struct timespec
{
    public
    {
        tv_sec:  s64
        tv_nsec: s64
    }
}

#assert(#sizeof(timespec) == 16)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func clock_gettime(clockid: s32, tp: *timespec)->s32
