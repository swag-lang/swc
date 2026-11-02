#global if #os == Swag.TargetOs.Linux
#global export

struct XScreenSaverInfo
{
    public
    {
        window: u64
        state: s32
        kind: s32
        til_or_since: u64
        idle: u64
        eventMask: u64
    }
}

#[Swag.CallingConvention(.C)]
{
    alias XDefaultRootWindow_fn = func(*void)->u64
    alias XScreenSaverQueryInfo_fn = func(*void, u64, *XScreenSaverInfo)->s32
}

#assert(#sizeof(XScreenSaverInfo) == 40)
