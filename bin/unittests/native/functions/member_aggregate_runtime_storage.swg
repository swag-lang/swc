#global private
#global #[Swag.ExplicitNullability]

struct NativeMemberAggregateRuntimeStorageHolder
{
    cb: func(bool)->#decltype({first: 50'u16, second: 51'u16})
}

#test
{
    let flag = false
    let holder = NativeMemberAggregateRuntimeStorageHolder{
        cb: func(v: bool)->#decltype({first: 50'u16, second: 51'u16}) {
            if v do
                return {first: 50'u16, second: 51'u16}
            return {first: 60'u16, second: 61'u16}
        }
    }

    @assert(holder.cb(flag).first == 60'u16)
    @assert(holder.cb(!flag).second == 51'u16)
}
