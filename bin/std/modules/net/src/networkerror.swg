#global export

// Reports a network operation failure with the host's diagnostic code.
struct NetworkError
{
    public
    {
        using base: Swag.BaseError     // Error state.
        code:       s32     // Host error code.
    }
}
