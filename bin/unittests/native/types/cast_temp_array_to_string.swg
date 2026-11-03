#global private

struct CastTempArrayToStringHolder
{
    cb: func(flag: bool)->[5] u8
}

#test
{
    let holder = CastTempArrayToStringHolder{
        cb: func(flag: bool)->[5] u8
    {
        if flag do
            return ['h'u8, 'e'u8, 'l'u8, 'l'u8, 'o'u8]
        return ['w'u8, 'o'u8, 'r'u8, 'l'u8, 'd'u8]
    }
        }

    let text  = cast(string, holder.cb(false))
    let bytes = cast(const [..] u8, text)
    Swag.require(bytes.count == 5)
    Swag.require(text[0] == 'w'u8)
    Swag.require(text[4] == 'd'u8)
}
