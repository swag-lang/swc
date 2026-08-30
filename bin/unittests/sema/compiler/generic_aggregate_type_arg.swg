#global private

func(T) takesType()->bool
{
    return #sizeof(T) >= 0
}

func semaTest001()
{
    Swag.assert(takesType'{ buf: const [..] u8, seek: u64 }())
    Swag.assert(takesType'{ compressed: bool, tmpBuf: *u8 }())
}
