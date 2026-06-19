#global fileprivate
using Swag

#test
{
    let both = (#type const [2] f32) and true
    let either = false or (#type func()->void)
    let selected = (#type s32) ? 10 : 20

    @assert(both)
    @assert(either)
    @assert(selected == 10)
}
