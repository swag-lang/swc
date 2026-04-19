#global fileprivate

func(T) takesType()->bool
{
    return #sizeof(T) >= 0
}

#test
{
    @assert(takesType'{ buf: const [..] u8, seek: u64 }())
    @assert(takesType'{ compressed: bool, tmpBuf: *u8 }())
}
