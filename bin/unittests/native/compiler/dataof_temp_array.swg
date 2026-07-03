#global private

struct DataOfTempArrayHolder
{
    cb: func(flag: bool)->[5] u8
}

#test
{
    let holder = DataOfTempArrayHolder{
        cb: func(flag: bool)->[5] u8 {
            if flag do
                return ['h''u8, 'e''u8, 'l''u8, 'l''u8, 'o''u8]
            return ['w''u8, 'o''u8, 'r''u8, 'l''u8, 'd''u8]
        },
    }

    let p = @dataof(holder.cb(false))
    @assert(p[0] == 'w''u8)
    @assert(p[4] == 'd''u8)
}
