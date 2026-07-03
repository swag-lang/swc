#global private

func autocastTempArrayToSliceConsume(values: const [..] u16) -> u16
{
    return values[0] + values[3]
}

#test
{
    let cb = func(flag: bool)->[4] u16 {
        if flag do
            return [10'u16, 20, 30, 40]
        return [50'u16, 60, 70, 80]
    }

    let view: const [..] u16 = cb(false)
    @assert(@countof(view) == 4)
    @assert(view[0] == 50'u16)
    @assert(view[3] == 80'u16)
    @assert(autocastTempArrayToSliceConsume(cb(false)) == 130'u16)
}
