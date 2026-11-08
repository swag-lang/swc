using FwdProvider

#test
{
    var value = FwdValue{3}
    store(value)
    Swag.require(copyCount() == 1)
    store(#move value)
    Swag.require(moveCount() == 1)
    var only = MoveOnly{7}
    storeMoveOnly(#move only)
    Swag.require(moveOnlyValue() == 7)
}

#main
{
}
