#global private

struct AutocastTempArrayToStringHolder
{
    cb: func(flag: bool)->[5] u8
}

func autocastTempArrayToStringConsume(text: string)->u8
{
    return text[0] + text[4]
}

#test
{
    let holder = AutocastTempArrayToStringHolder{
        cb: func(flag: bool)->[5] u8
    {
        if flag do
            return ['h''u8, 'e''u8, 'l''u8, 'l''u8, 'o''u8]
        return ['w''u8, 'o''u8, 'r''u8, 'l''u8, 'd''u8]
    },
        }

    let text: string = holder.cb(false)
    let bytes = cast(const [..] u8) text
    @assert(@countof(bytes) == 5)
    @assert(text[0] == 'w''u8)
    @assert(text[4] == 'd''u8)
    @assert(autocastTempArrayToStringConsume(holder.cb(false)) == 'w''u8 + 'd''u8)
}
