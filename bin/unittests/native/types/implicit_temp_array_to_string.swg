#global private

struct ImplicitTempArrayToStringHolder
{
    cb: func(flag: bool)->[5] u8
}

func implicitTempArrayToStringConsume(text: string)->u8
{
    return text[0] + text[4]
}

#test
{
    let holder = ImplicitTempArrayToStringHolder{
        cb: func(flag: bool)->[5] u8
    {
        if flag do
            return ['h'u8, 'e'u8, 'l'u8, 'l'u8, 'o'u8]
        return ['w'u8, 'o'u8, 'r'u8, 'l'u8, 'd'u8]
    }
        }

    let text: string = holder.cb(false)
    let bytes        = cast(const [..] u8, text)
    Swag.require(bytes.count == 5)
    Swag.require(text[0] == 'w'u8)
    Swag.require(text[4] == 'd'u8)
    Swag.require(implicitTempArrayToStringConsume(holder.cb(false)) == 'w'u8 + 'd'u8)
}
