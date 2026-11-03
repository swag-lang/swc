#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var left  = 10
    var right = -4
    Core.swap(&left, &right)
    Swag.require(left == -4)
    Swag.require(right == 10)

    var first:  String = "alpha"
    var second: String = "beta"
    Core.swap(&first, &second)
    Swag.require(first == "beta")
    Swag.require(second == "alpha")
}

#test
{
    var low  = 9
    var high = -3
    Core.orderMinMax(&low, &high)
    Swag.require(low == -3)
    Swag.require(high == 9)

    var sameLeft  = 4
    var sameRight = 4
    Core.orderMinMax(&sameLeft, &sameRight)
    Swag.require(sameLeft == 4)
    Swag.require(sameRight == 4)
}

#test
{
    var high = -1
    var low  = 12
    Core.orderMaxMin(&high, &low)
    Swag.require(high == 12)
    Swag.require(low == -1)

    var sameLeft  = 7
    var sameRight = 7
    Core.orderMaxMin(&sameLeft, &sameRight)
    Swag.require(sameLeft == 7)
    Swag.require(sameRight == 7)
}
