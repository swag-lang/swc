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

struct tm
{
    public
    {
        tm_sec:    s32
        tm_min:    s32
        tm_hour:   s32
        tm_mday:   s32
        tm_mon:    s32
        tm_year:   s32
        tm_wday:   s32
        tm_yday:   s32
        tm_isdst:  s32
        tm_gmtoff: s64
        tm_zone:   const [*] u8?
    }
}

#assert(#sizeof(tm) == 56)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func gmtime_r(timer: const *s64, result: *tm)->*tm?
    func localtime_r(timer: const *s64, result: *tm)->*tm?
    func timegm(timeptr: *tm)->s64
    func mktime(timeptr: *tm)->s64
}
