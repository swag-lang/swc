#global private

struct SliceTempArrayRuntimeStorageHolder
{
    cb: func(flag: bool)->[4] u16
}

#test
{
    let holder = SliceTempArrayRuntimeStorageHolder{
        cb: func(flag: bool)->[4] u16
    {
        if flag do
            return [11'u16, 12, 13, 14]
        return [21'u16, 22, 23, 24]
    }
        }

    let tail = holder.cb(true)[2 to]
    Swag.require(tail.count == 2)
    Swag.require(tail[0] == 13'u16)
    Swag.require(tail[1] == 14'u16)
}
