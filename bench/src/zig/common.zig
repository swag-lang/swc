// Shared RNG, Windows performance counter and CRT allocation, as in the C++ port.
extern "kernel32" fn QueryPerformanceCounter(counter: *i64) callconv(.winapi) i32;
extern "kernel32" fn QueryPerformanceFrequency(frequency: *i64) callconv(.winapi) i32;
extern "c" fn printf(format: [*:0]const u8, ...) c_int;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn exit(code: c_int) noreturn;
pub extern "c" fn free(ptr: ?*anyopaque) void;
pub extern "c" fn memcmp(left: [*]const u8, right: [*]const u8, n: usize) c_int;

var seed: u64 = 12345;

pub fn rnd() u64 {
    seed = (seed * 16807) % 2147483647;
    return seed;
}

pub fn now() f64 {
    var counter: i64 = undefined;
    var frequency: i64 = undefined;
    _ = QueryPerformanceCounter(&counter);
    _ = QueryPerformanceFrequency(&frequency);
    return @as(f64, @floatFromInt(counter)) / @as(f64, @floatFromInt(frequency));
}

pub fn report(check: u64, t0: f64, t1: f64) void {
    _ = printf("CHECK=%llu MS=%.6f\n", check, (t1 - t0) * 1000.0);
}

pub fn xalloc(n: usize) *anyopaque {
    return malloc(n) orelse exit(1);
}

pub fn memcpy(dst: [*]u8, src: [*]const u8, n: usize) void {
    @memcpy(dst[0..n], src[0..n]);
}

pub fn memset(dst: [*]u8, value: u8, n: usize) void {
    @memset(dst[0..n], value);
}
