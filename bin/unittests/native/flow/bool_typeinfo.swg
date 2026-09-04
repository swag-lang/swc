#global private
using Swag

// Every statement that takes a condition accepts a type value. The values are bound as
// '? typeinfo' variables: a type that can never be null refuses the question, because the
// answer could only be true.

#test
{
    var intType:   typeinfo? = #type s32
    var floatType: typeinfo? = #type f32
    var arrayType: typeinfo? = #type const [2] u8
    var funcType:  typeinfo? = #type func()->s32

    var count = 0
    if intType do
        count += 1

    while floatType
    {
        count += 1
        break
    }

    for i in 4 where arrayType do
        count += 1

    var switchHit = 0
    switch 1
    {
    case 1 where arrayType:
        switchHit += 1
        break
    }

    switch
    {
    case funcType:
        switchHit += 10
        break
    default:
        switchHit += 100
        break
    }

    Swag.assert(count == 6)
    Swag.assert(switchHit == 11)

    intType = null
    Swag.assert(!intType)
}
