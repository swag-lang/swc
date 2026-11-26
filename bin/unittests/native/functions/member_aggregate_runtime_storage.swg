#global private

struct NativeMemberAggregateRuntimeStorageHolder
{
    cb: func(bool)->#decltype({first: 50_u16, second: 51_u16})
}

#test
{
    let flag   = false
    let holder = NativeMemberAggregateRuntimeStorageHolder{
        cb: func(v: bool)->#decltype({first: 50_u16, second: 51_u16})
    {
        if v
        {
            return {first: 50_u16, second: 51_u16}
        }
        return {first: 60_u16, second: 61_u16}
    }
        }

    Swag.require(holder.cb(flag).first == 60_u16)
    Swag.require(holder.cb(not flag).second == 51_u16)
}
