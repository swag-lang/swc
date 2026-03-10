#global export
using Swag

#[Foreign(module: ForeignLib, link: ForeignLink)]
{
    func clock()->clock_t;
    func mktime(timeptr: *tm)->time_t;
    func asctime(timeptr: *tm)->*u8;
    func strftime(s: *u8, maxsize: size_t, format: const *u8, timeptr: *tm)->size_t;
}

#if #os == Swag.TargetOs.Windows
{
    #[Foreign(module: ForeignLib, function: "_difftime64", link: ForeignLink)]
    func difftime(time1, time2: time_t)->f64;
    #[Foreign(module: ForeignLib, function: "_time64", link: ForeignLink)]
    func time(timer: *time_t)->time_t;
    #[Foreign(module: ForeignLib, function: "_gmtime64", link: ForeignLink)]
    func gmtime(timer: *time_t)->*tm;
    #[Foreign(module: ForeignLib, function: "_localtime64", link: ForeignLink)]
    func localtime(timer: *time_t)->*tm;
    #[Foreign(module: ForeignLib, function: "_ctime64", link: ForeignLink)]
    func ctime(timer: const *time_t)->*u8;
}

const CLOCKS_PER_SEC = 1000
const TIME_UTC       = 1

alias clock_t = s64
alias time_t  = s64

struct tm
{
    tm_sec:       s32
    tm_min:       s32
    tm_hour:      s32
    tm_mday:      s32
    tm_mon:       s32
    tm_year:      s32
    tm_wday:      s32
    tm_yday:      s32
    tm_isdst:     s32
}
