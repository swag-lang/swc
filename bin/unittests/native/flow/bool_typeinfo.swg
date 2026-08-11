#global private
using Swag

#test
{
    var count = 0
    if #type s32 do
        count += 1

    while #type f32
    {
        count += 1
        break
    }

    for i in 4 where (#type const [2] u8) do
        count += 1

    var switchHit = 0
    switch 1
    {
    case 1 where #type const [2] u8:
        switchHit += 1
        break
    }

    switch
    {
    case #type func()->s32:
        switchHit += 10
        break
    default:
        switchHit += 100
        break
    }

    @assert(count == 6)
    @assert(switchHit == 11)
}
