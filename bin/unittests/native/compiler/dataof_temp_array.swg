#global private

struct DataOfTempArrayHolder
{
    cb: func(flag: bool)->[5] u8
}

#test
{
    let holder = DataOfTempArrayHolder{
        cb: func(flag: bool)->[5] u8
    {
        if flag
        {
            return ['h'_u8, 'e'_u8, 'l'_u8, 'l'_u8, 'o'_u8]
        }
        return ['w'_u8, 'o'_u8, 'r'_u8, 'l'_u8, 'd'_u8]
    }
        }

    let p = (holder.cb(false)).buffer
    Swag.require(p[0] == 'w'_u8)
    Swag.require(p[4] == 'd'_u8)
}
