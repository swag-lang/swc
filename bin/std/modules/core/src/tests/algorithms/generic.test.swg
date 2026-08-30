#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var left  = 10
    var right = -4
    Core.swap(&left, &right)
    Swag.assert(left == -4)
    Swag.assert(right == 10)

    var first:  String = "alpha"
    var second: String = "beta"
    Core.swap(&first, &second)
    Swag.assert(first == "beta")
    Swag.assert(second == "alpha")
}

#test
{
    var low  = 9
    var high = -3
    Core.orderMinMax(&low, &high)
    Swag.assert(low == -3)
    Swag.assert(high == 9)

    var sameLeft  = 4
    var sameRight = 4
    Core.orderMinMax(&sameLeft, &sameRight)
    Swag.assert(sameLeft == 4)
    Swag.assert(sameRight == 4)
}

#test
{
    var high = -1
    var low  = 12
    Core.orderMaxMin(&high, &low)
    Swag.assert(high == 12)
    Swag.assert(low == -1)

    var sameLeft  = 7
    var sameRight = 7
    Core.orderMaxMin(&sameLeft, &sameRight)
    Swag.assert(sameLeft == 7)
    Swag.assert(sameRight == 7)
}
