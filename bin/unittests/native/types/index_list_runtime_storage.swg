#global private

struct NativeIndexListRuntimeStorageCallbackHolder
{
    cb: func(bool)->[2, 2] u16
}

#test
{
    let flag   = false
    let holder = NativeIndexListRuntimeStorageCallbackHolder{
        cb: func(v: bool)->[2, 2] u16
    {
        if v
        {
            return [[50_u16, 51], [52, 53]]
        }
        return [[60_u16, 61], [62, 63]]
    }
        }

    Swag.require(holder.cb(flag)[1, 0] == 62_u16)
    Swag.require(holder.cb(flag)[0, 1] == 61_u16)
}
