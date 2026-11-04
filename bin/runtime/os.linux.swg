#global if #os == Swag.TargetOs.Linux

#foreignlib("c")
#foreignlib("m")

// GNU/Linux x86-64 runtime bootstrap. These declarations cannot depend on std/core.
namespace __LinuxRT
{
    #[Swag.CallingConvention(.C)]
    alias ThreadCleanup = func(*void?)

    struct Timespec
    {
        seconds:     s64
        nanoseconds: s64
    }

    const ClockMonotonic = 1's32
    const FutexWaitPrivate = 128's32
    const FutexWakePrivate = 129's32
    const FutexSyscall = 202's64
    const Interrupted = 4's32
    const WouldBlock = 11's32
    const TimedOut = 110's32

    #[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
    {
        func pthread_key_create(key: *u32, cleanup: ThreadCleanup?)->s32
        func pthread_key_delete(key: u32)->s32
        func pthread_getspecific(key: u32)->*void?
        func pthread_setspecific(key: u32, value: const *void?)->s32
        func gettid()->s32
        func clock_gettime(clock: s32, value: *Timespec)->s32
        func nanosleep(duration: const *Timespec, remaining: *Timespec?)->s32
        func sched_yield()->s32
        func __errno_location()->*s32
        // Fixed declaration of the six-argument futex operation: all arguments are integer
        // class, so its System V call also satisfies syscall's variadic register contract.
        func syscall(number: s64, address: *u32, operation: s32, value: u32, timeout: const *Timespec?, other: *u32?, value3: u32)->s64
    }
}

// Linux x86-64 has 4 KiB base pages; huge pages are not part of the bootstrap allocator.
const AllocatorHostCommitGranularity = 4096'u64

func __hostTlsAlloc()->u64
{
    var key: u32
    return __LinuxRT.pthread_key_create(&key, null) == 0 ? cast(u64, key) : Swag.U64.Max
}

func __hostTlsFree(id: u64)
{
    discard __LinuxRT.pthread_key_delete(cast(u32, id))
}

#[Swag.Inline]
func __hostTlsGet(id: u64)->*void? => __LinuxRT.pthread_getspecific(cast(u32, id))
func __hostTlsSet(id: u64, value: *void?)->bool => __LinuxRT.pthread_setspecific(cast(u32, id), value) == 0

// Destructor-bearing keys use zero for failure and key + 1 for a live slot.
func __hostThreadStorageAlloc(cleanup: __LinuxRT.ThreadCleanup?)->u64
{
    var key: u32
    return __LinuxRT.pthread_key_create(&key, cleanup) == 0 ? cast(u64, key) + 1 : 0
}

func __hostThreadStorageFree(id: u64)
{
    if id do
        discard __LinuxRT.pthread_key_delete(cast(u32, (id - 1)))
}

func __hostThreadStorageGet(id: u64)->*void? => id ? __LinuxRT.pthread_getspecific(cast(u32, (id - 1))) : null
func __hostThreadStorageSet(id: u64, value: *void?)->bool => id != 0 and __LinuxRT.pthread_setspecific(cast(u32, (id - 1)), value) == 0
func __hostCurrentThreadId()->u64 => cast(u64, __LinuxRT.gettid())

func __hostMonotonicTicks()->u64
{
    var value: __LinuxRT.Timespec
    discard __LinuxRT.clock_gettime(__LinuxRT.ClockMonotonic, &value)
    return cast(u64, value.seconds) * 1_000_000_000 + cast(u64, value.nanoseconds)
}

func __hostMonotonicFrequency()->u64 => 1_000_000_000

func __hostThreadYield()
{
    discard __LinuxRT.sched_yield()
}

func __hostThreadSleep(milliseconds: u32)
{
    var duration = __LinuxRT.Timespec{seconds: cast(s64, milliseconds / 1000), nanoseconds: cast(s64, milliseconds % 1000) * 1_000_000}
    while __LinuxRT.nanosleep(&duration, &duration) != 0
    {
        if __LinuxRT.__errno_location()[] != __LinuxRT.Interrupted do
            return
    }
}

// The common lock has one pointer-sized word, initialized to zero. Its low 32 bits hold
// a reader count or the writer bit; futex waits need neither a heap object nor destruction.
private const LinuxWriter = 0x8000_0000'u32

#[Swag.Safety(.ValueBorrow, false)]
private func __linuxWake(address: *u32, count: u32)
{
    discard __LinuxRT.syscall(__LinuxRT.FutexSyscall, address, __LinuxRT.FutexWakePrivate, count, null, null, 0)
}

#[Swag.Safety(.ValueBorrow, false)]
func __hostTryLockExclusive(lock: *(*void?))->bool => Swag.atomicCompareExchange(cast(*u32, lock), 0, LinuxWriter) == 0

#[Swag.Safety(.ValueBorrow, false)]
func __hostLockExclusive(lock: *(*void?))
{
    let state = cast(*u32, lock)
    while not __hostTryLockExclusive(lock)
    {
        let observed = Swag.atomicLoad(state)
        if observed do
            discard __LinuxRT.syscall(__LinuxRT.FutexSyscall, state, __LinuxRT.FutexWaitPrivate, observed, null, null, 0)
    }
}

#[Swag.Safety(.ValueBorrow, false)]
func __hostUnlockExclusive(lock: *(*void?))
{
    let state = cast(*u32, lock)
    Swag.atomicStore(state, 0)
    __linuxWake(state, 0x7FFF_FFFF)
}

#[Swag.Safety(.ValueBorrow, false)]
func __hostTryLockShared(lock: *(*void?))->bool
{
    let state = cast(*u32, lock)
    var observed = Swag.atomicLoad(state)
    for
    {
        if observed >= LinuxWriter - 1 do
            return false
        let previous = Swag.atomicCompareExchange(state, observed, observed + 1)
        if previous == observed do
            return true
        observed = previous
    }
}

#[Swag.Safety(.ValueBorrow, false)]
func __hostLockShared(lock: *(*void?))
{
    let state = cast(*u32, lock)
    while not __hostTryLockShared(lock)
    {
        let observed = Swag.atomicLoad(state)
        if observed >= LinuxWriter - 1 do
            discard __LinuxRT.syscall(__LinuxRT.FutexSyscall, state, __LinuxRT.FutexWaitPrivate, observed, null, null, 0)
    }
}

#[Swag.Safety(.ValueBorrow, false)]
func __hostUnlockShared(lock: *(*void?))
{
    let state = cast(*u32, lock)
    let previous = Swag.atomicAdd(state, Swag.U32.Max)
    if previous == 1 or previous == LinuxWriter - 1 do
        __linuxWake(state, 0x7FFF_FFFF)
}

func __hostConditionInit(condition: *(*void?))
{
    condition[] = null
}

#[Swag.Safety(.ValueBorrow, false)]
func __hostConditionWake(condition: *(*void?))
{
    let sequence = cast(*u32, condition)
    discard Swag.atomicAdd(sequence, 1)
    __linuxWake(sequence, 1)
}

#[Swag.Safety(.ValueBorrow, false)]
func __hostConditionWakeAll(condition: *(*void?))
{
    let sequence = cast(*u32, condition)
    discard Swag.atomicAdd(sequence, 1)
    __linuxWake(sequence, 0x7FFF_FFFF)
}

// Snapshot while holding the mutex. FUTEX_WAIT checks that value atomically before sleeping,
// so a wake racing with the unlock cannot disappear between the two operations.
#[Swag.Safety(.ValueBorrow, false)]
func __hostConditionWait(condition: *(*void?), lock: *(*void?), milliseconds: u32)->bool
{
    let sequence = cast(*u32, condition)
    let observed = Swag.atomicLoad(sequence)
    let finite = milliseconds != Swag.InfiniteWait
    let deadline = finite ? __hostMonotonicTicks() + cast(u64, milliseconds) * 1_000_000 : 0'u64
    __hostUnlockExclusive(lock)
    defer __hostLockExclusive(lock)

    for
    {
        var duration: __LinuxRT.Timespec
        var timeout: const *__LinuxRT.Timespec?
        if finite
        {
            let now = __hostMonotonicTicks()
            if now >= deadline do
                return false
            let remaining = deadline - now
            duration.seconds = cast(s64, remaining / 1_000_000_000)
            duration.nanoseconds = cast(s64, remaining % 1_000_000_000)
            timeout = &duration
        }

        let result = __LinuxRT.syscall(__LinuxRT.FutexSyscall, sequence, __LinuxRT.FutexWaitPrivate, observed, timeout, null, 0)
        if result == 0 do
            return true
        let error = __LinuxRT.__errno_location()[]
        if error != __LinuxRT.Interrupted do
            return error == __LinuxRT.WouldBlock
    }
}

#[Swag.NoDoc]
struct MutexRW
{
    v: *void?
}

#[Swag.NoDoc]
impl MutexRW
{
    mtd lock() => __hostLockExclusive(&.v)
    mtd unlock() => __hostUnlockExclusive(&.v)
}

// HOSTED MATH

namespace __LinuxRT
{
    #[Swag.Foreign(module: "libm.so.6", link: "m", callconv: Swag.CallConv.C)]
    {
        func sinf(val: f32)->f32
        func cosf(val: f32)->f32
        func tanf(val: f32)->f32
        func sinhf(val: f32)->f32
        func coshf(val: f32)->f32
        func tanhf(val: f32)->f32
        func asinf(val: f32)->f32
        func acosf(val: f32)->f32
        func atanf(val: f32)->f32
        func logf(val: f32)->f32
        func log2f(val: f32)->f32
        func log10f(val: f32)->f32
        func expf(val: f32)->f32
        func exp2f(val: f32)->f32

        func sin(val: f64)->f64
        func cos(val: f64)->f64
        func tan(val: f64)->f64
        func sinh(val: f64)->f64
        func cosh(val: f64)->f64
        func tanh(val: f64)->f64
        func asin(val: f64)->f64
        func acos(val: f64)->f64
        func atan(val: f64)->f64
        func log(val: f64)->f64
        func log2(val: f64)->f64
        func log10(val: f64)->f64
        func exp(val: f64)->f64
        func exp2(val: f64)->f64

        func powf(val1, val2: f32)->f32
        func atan2f(val1, val2: f32)->f32
        func pow(val1, val2: f64)->f64
        func atan2(val1, val2: f64)->f64
    }
}

// INTRINSIC WRAPPERS

{
    func sin(value: f32)->f32 => __LinuxRT.sinf(value)
    func sin(value: f64)->f64 => __LinuxRT.sin(value)
    func cos(value: f32)->f32 => __LinuxRT.cosf(value)
    func cos(value: f64)->f64 => __LinuxRT.cos(value)
    func tan(value: f32)->f32 => __LinuxRT.tanf(value)
    func tan(value: f64)->f64 => __LinuxRT.tan(value)

    func sinh(value: f32)->f32 => __LinuxRT.sinhf(value)
    func sinh(value: f64)->f64 => __LinuxRT.sinh(value)
    func cosh(value: f32)->f32 => __LinuxRT.coshf(value)
    func cosh(value: f64)->f64 => __LinuxRT.cosh(value)
    func tanh(value: f32)->f32 => __LinuxRT.tanhf(value)
    func tanh(value: f64)->f64 => __LinuxRT.tanh(value)

    func asin(value: f32)->f32 => __LinuxRT.asinf(value)
    func asin(value: f64)->f64 => __LinuxRT.asin(value)
    func acos(value: f32)->f32 => __LinuxRT.acosf(value)
    func acos(value: f64)->f64 => __LinuxRT.acos(value)
    func atan(value: f32)->f32 => __LinuxRT.atanf(value)
    func atan(value: f64)->f64 => __LinuxRT.atan(value)

    func log(value: f32)->f32   => __LinuxRT.logf(value)
    func log(value: f64)->f64   => __LinuxRT.log(value)
    func log2(value: f32)->f32  => __LinuxRT.log2f(value)
    func log2(value: f64)->f64  => __LinuxRT.log2(value)
    func log10(value: f32)->f32 => __LinuxRT.log10f(value)
    func log10(value: f64)->f64 => __LinuxRT.log10(value)

    func exp(value: f32)->f32  => __LinuxRT.expf(value)
    func exp(value: f64)->f64  => __LinuxRT.exp(value)
    func exp2(value: f32)->f32 => __LinuxRT.exp2f(value)
    func exp2(value: f64)->f64 => __LinuxRT.exp2(value)

    func pow(value1, value2: f32)->f32 => __LinuxRT.powf(value1, value2)
    func pow(value1, value2: f64)->f64 => __LinuxRT.pow(value1, value2)

    func atan2(value1, value2: f32)->f32 => __LinuxRT.atan2f(value1, value2)
    func atan2(value1, value2: f64)->f64 => __LinuxRT.atan2(value1, value2)
}

