#global if #os == Swag.TargetOs.Linux
#global export

// Optional systemd login/session APIs. Callers own the library, bus, messages and returned strings.
// Signatures follow https://www.freedesktop.org/software/systemd/man/latest/sd-bus.html.
#[Swag.CallingConvention(.C)]
{
    alias sd_bus_open_system_fn = func(*(*void?))->s32
    alias sd_bus_unref_fn = func(*void?)->*void?
    alias sd_bus_set_method_call_timeout_fn = func(*void, u64)->s32
    alias sd_bus_get_property_trivial_fn = func(*void, const [*]u8, const [*]u8, const [*]u8, const [*]u8, *void?, u8, *void)->s32
    alias sd_bus_call_method_fn = func(*void, const [*]u8, const [*]u8, const [*]u8, const [*]u8, *void?, *(*void?), const [*]u8, ...)->s32
    alias sd_bus_message_read_fn = func(*void, const [*]u8, ...)->s32
    alias sd_bus_message_unref_fn = func(*void?)->*void?
    alias sd_pid_get_session_fn = func(s32, *([*]u8?))->s32
    alias sd_bus_path_encode_fn = func(const [*]u8, const [*]u8, *([*]u8?))->s32
}
