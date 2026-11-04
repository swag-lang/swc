#global if #os == Swag.TargetOs.Linux
#global export

// Optional systemd login/session APIs.
//
// Callers own the library, bus, messages and returned strings.
// Signatures follow https://www.freedesktop.org/software/systemd/man/latest/sd-bus.html.
#[Swag.CallingConvention(.C)]
alias sd_bus_message_handler_t          = func(*void, *void?, *void?)->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_process_fn                 = func(*void, *(*void?)?)->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_add_match_fn               = func(*void, *(*void?)?, const [*]u8, sd_bus_message_handler_t, *void?)->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_message_enter_container_fn = func(*void, u8, const [*]u8)->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_message_exit_container_fn  = func(*void)->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_message_skip_fn            = func(*void, const [*]u8)->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_open_system_fn             = func(*(*void?))->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_unref_fn                   = func(*void?)->*void?

#[Swag.CallingConvention(.C)]
alias sd_bus_set_method_call_timeout_fn = func(*void, u64)->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_get_property_trivial_fn    = func(*void, const [*]u8, const [*]u8, const [*]u8, const [*]u8, *void?, u8, *void)->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_call_method_fn             = func(*void, const [*]u8, const [*]u8, const [*]u8, const [*]u8, *void?, *(*void?), const [*]u8, ...)->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_message_read_fn            = func(*void, const [*]u8, ...)->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_message_unref_fn           = func(*void?)->*void?

#[Swag.CallingConvention(.C)]
alias sd_pid_get_session_fn             = func(s32, *([*]u8?))->s32

#[Swag.CallingConvention(.C)]
alias sd_bus_path_encode_fn             = func(const [*]u8, const [*]u8, *([*]u8?))->s32

// Opens an owned connection to the calling user's D-Bus session.
#[Swag.CallingConvention(.C)]
alias sd_bus_open_user_fn = func(*(*void?))->s32

// Reports whether a D-Bus connection remains open.
#[Swag.CallingConvention(.C)]
alias sd_bus_is_open_fn = func(*void)->s32
