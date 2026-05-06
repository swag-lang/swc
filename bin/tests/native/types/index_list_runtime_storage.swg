#global fileprivate

struct NativeIndexListRuntimeStorageCallbackHolder
{
    cb: func(bool)->[2, 2] u16
}

#test
{
    let flag = false
    let holder = NativeIndexListRuntimeStorageCallbackHolder{
        cb: func(v: bool)->[2, 2] u16 {
            if v do
                return [[50'u16, 51], [52, 53]]
            return [[60'u16, 61], [62, 63]]
        }
    }

    @assert(holder.cb(flag)[1, 0] == 62'u16)
    @assert(holder.cb(flag)[0, 1] == 61'u16)
}
