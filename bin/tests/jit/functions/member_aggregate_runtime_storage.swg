#global fileprivate

#test
{
    let cb = func(v: bool)->#decltype({first: 31'u16, second: 32'u16}) {
        if v do
            return {first: 31'u16, second: 32'u16}
        return {first: 41'u16, second: 42'u16}
    }

    @assert(cb(false).first == 41'u16)
    @assert(cb(true).second == 32'u16)
}
