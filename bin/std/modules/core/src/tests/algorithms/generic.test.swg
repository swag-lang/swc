#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    var left  = 10
    var right = -4
    Core.swap(&left, &right)
    @assert(left == -4)
    @assert(right == 10)

    var first: String  = "alpha"
    var second: String = "beta"
    Core.swap(&first, &second)
    @assert(first == "beta")
    @assert(second == "alpha")
}

#test
{
    var low  = 9
    var high = -3
    Core.orderMinMax(&low, &high)
    @assert(low == -3)
    @assert(high == 9)

    var sameLeft  = 4
    var sameRight = 4
    Core.orderMinMax(&sameLeft, &sameRight)
    @assert(sameLeft == 4)
    @assert(sameRight == 4)
}

#test
{
    var high = -1
    var low  = 12
    Core.orderMaxMin(&high, &low)
    @assert(high == 12)
    @assert(low == -1)

    var sameLeft  = 7
    var sameRight = 7
    Core.orderMaxMin(&sameLeft, &sameRight)
    @assert(sameLeft == 7)
    @assert(sameRight == 7)
}
