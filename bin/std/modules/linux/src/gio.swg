#global if #os == Swag.TargetOs.Linux
#global export

// Optional GIO desktop integration. Object and allocated-string ownership follows GLib.
// https://docs.gtk.org/gio/ and https://docs.gtk.org/glib/
#[Swag.CallingConvention(.C)]
alias g_desktop_app_info_new_from_filename_fn = func(const [*] u8)->*void?

#[Swag.CallingConvention(.C)]
alias g_app_info_add_supports_type_fn         = func(*void, const [*] u8, *(*void?)?)->s32

#[Swag.CallingConvention(.C)]
alias g_app_info_set_as_default_for_type_fn   = func(*void, const [*] u8, *(*void?)?)->s32

#[Swag.CallingConvention(.C)]
alias g_content_type_guess_fn                 = func(const [*] u8?, const [*] u8?, u64, *s32?)->[*] u8?

#[Swag.CallingConvention(.C)]
alias g_object_unref_fn                       = func(*void)
