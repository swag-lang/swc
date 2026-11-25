#global export
#global if #os == Swag.TargetOs.Linux
#global namespace Cups

struct cups_option_t
{
    public
    {
        name:  const [*] u8?
        value: const [*] u8?
    }
}

struct cups_dest_t
{
    public
    {
        name:        const [*] u8?
        instance:    const [*] u8?
        is_default:  s32
        num_options: s32
        options:     [*] cups_option_t?
    }
}

struct cups_size_t
{
    public
    {
        media:  [128] u8
        width:  s32
        length: s32
        bottom: s32
        left:   s32
        right:  s32
        top:    s32
    }
}

#[Swag.Opaque]
struct cups_dinfo_t
{
    private opaque: u8
}

#[Swag.CallingConvention(.C)]
alias cupsGetDestsFunc           = func(*([*] cups_dest_t?))->s32
#[Swag.CallingConvention(.C)]
alias cupsFreeDestsFunc          = func(s32, [*] cups_dest_t?)
#[Swag.CallingConvention(.C)]
alias cupsGetNamedDestFunc       = func(*void?, const [*] u8?, const [*] u8?)->[*] cups_dest_t?
#[Swag.CallingConvention(.C)]
alias cupsCopyDestInfoFunc       = func(*void?, *cups_dest_t)->*cups_dinfo_t?
#[Swag.CallingConvention(.C)]
alias cupsFreeDestInfoFunc       = func(*cups_dinfo_t)
#[Swag.CallingConvention(.C)]
alias cupsGetDestMediaByNameFunc = func(*void?, *cups_dest_t, *cups_dinfo_t, const [*] u8, u32, *cups_size_t)->s32
#[Swag.CallingConvention(.C)]
alias cupsPrintFileFunc          = func(const [*] u8, const [*] u8, const [*] u8, s32, const [*] cups_option_t)->s32
#[Swag.CallingConvention(.C)]
alias cupsCancelJobFunc          = func(const [*] u8, s32)->s32

const CUPS_MEDIA_FLAGS_DEFAULT = 0'u32
