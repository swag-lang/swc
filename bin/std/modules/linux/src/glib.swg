#global if #os == Swag.TargetOs.Linux
#global export

const G_KEY_FILE_KEEP_COMMENTS     = 1's32
const G_KEY_FILE_KEEP_TRANSLATIONS = 2's32

#[Swag.CallingConvention(.C)]
alias g_key_file_new_fn            = func()->*void

#[Swag.CallingConvention(.C)]
alias g_key_file_unref_fn          = func(*void)

#[Swag.CallingConvention(.C)]
alias g_key_file_load_from_file_fn = func(*void, const [*] u8, s32, *(*void?)?)->s32

#[Swag.CallingConvention(.C)]
alias g_key_file_has_key_fn        = func(*void, const [*] u8, const [*] u8, *(*void?)?)->s32

#[Swag.CallingConvention(.C)]
alias g_key_file_set_string_fn     = func(*void, const [*] u8, const [*] u8, const [*] u8)

#[Swag.CallingConvention(.C)]
alias g_key_file_to_data_fn        = func(*void, *u64?, *(*void?)?)->[*] u8?

#[Swag.CallingConvention(.C)]
alias g_file_set_contents_fn       = func(const [*] u8, const [*] u8, s64, *(*void?)?)->s32

#[Swag.CallingConvention(.C)]
alias g_markup_escape_text_fn      = func(const [*] u8, s64)->[*] u8?

#[Swag.CallingConvention(.C)]
alias g_free_fn                    = func(*void?)
