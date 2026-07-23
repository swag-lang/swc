#global private

#test
{
    let cb = func(flag: bool)->[4] u16
    {
        if flag do
            return [10'u16, 20, 30, 40]
        return [50'u16, 60, 70, 80]
    }

    let view = cast(const [..] u16) cb(false)
    @assert(@countof(view) == 4)
    @assert(view[0] == 50'u16)
    @assert(view[3] == 80'u16)
}
