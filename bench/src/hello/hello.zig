extern "c" fn printf(format: [*:0]const u8, ...) c_int;

pub fn main() void {
    _ = printf("hello, world\n");
}
