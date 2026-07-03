#global private

#test
{
    let cb = func(flag: bool)->[4] u16 {
        if flag do
            return [10'u16, 20, 30, 40]
        return [50'u16, 60, 70, 80]
    }

    let p = @dataof(cb(false))
    @assert(p[0] == 50'u16)
    @assert(p[3] == 80'u16)
}
