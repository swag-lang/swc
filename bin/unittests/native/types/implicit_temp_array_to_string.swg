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
        if flag
        {
            return ['h'_u8, 'e'_u8, 'l'_u8, 'l'_u8, 'o'_u8]
        }
        return ['w'_u8, 'o'_u8, 'r'_u8, 'l'_u8, 'd'_u8]
    }
        }

    let text: string = holder.cb(false)
    let bytes        = cast(const [..] u8, text)
    Swag.require(bytes.count == 5)
    Swag.require(text[0] == 'w'_u8)
    Swag.require(text[4] == 'd'_u8)
    Swag.require(implicitTempArrayToStringConsume(holder.cb(false)) == 'w'_u8 + 'd'_u8)
}
