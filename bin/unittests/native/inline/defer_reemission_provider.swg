#global internal

namespace InlineDeferReemission
{
    struct CleanupError
    {
        using base: Swag.BaseError
        code:       s32 = 0
    }

    #[Swag.NoInline]
    func nativeHandle(value: u64)->u64 => value

    #[Swag.NoInline]
    func raiseCleanupError() fail
    {
        fail CleanupError{base: Swag.BaseError{"cleanup"}, code: 1}
    }

    // A cleanup body reaches this twice when its statement applies to two exits. The constants it
    // materializes belong to the exit that emitted them, so the second copy must build its own.
    #[Swag.Inline]
    func scaled(value: u64)->u64 => nativeHandle(value) * 3

    // A fallible cleanup helper: its 'return', and the failure its 'catch' swallows, leave this
    // expansion only, not the function whose exit is running the cleanup.
    #[Swag.Inline]
    func release(handle: u64)->u64 fail
    {
        let native = nativeHandle(handle)
        if native == cast #bit (u64) -1 do
            raiseCleanupError()
        return native
    }
}
