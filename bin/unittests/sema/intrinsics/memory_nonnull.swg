#global private

// Memory intrinsics require addresses even when no bytes are requested.
func rejectNullFillTarget()
{
    Swag.memset(null, 0, 0) // swc-expected-error {{sema_err_cannot_cast}}
}

func rejectNullCopyTarget()
{
    var byte: u8
    Swag.memcpy(null, &byte, 0) // swc-expected-error {{sema_err_cannot_cast}}
}

func rejectNullCopySource()
{
    var byte: u8
    Swag.memcpy(&byte, null, 0) // swc-expected-error {{sema_err_cannot_cast}}
}

func rejectNullMoveTarget()
{
    var byte: u8
    Swag.memmove(null, &byte, 0) // swc-expected-error {{sema_err_cannot_cast}}
}

func rejectNullMoveSource()
{
    var byte: u8
    Swag.memmove(&byte, null, 0) // swc-expected-error {{sema_err_cannot_cast}}
}

func rejectNullCompareLeft()
{
    var byte: u8
    discard Swag.memcmp(null, &byte, 0) // swc-expected-error {{sema_err_cannot_cast}}
}

func rejectNullCompareRight()
{
    var byte: u8
    discard Swag.memcmp(&byte, null, 0) // swc-expected-error {{sema_err_cannot_cast}}
}
