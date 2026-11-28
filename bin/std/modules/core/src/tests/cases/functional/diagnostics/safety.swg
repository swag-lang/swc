#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func safetyCondition(count: *s32, value: bool)->bool
{
    count[] += 1
    return value
}

#[Swag.Safety(.BoundCheck, false)]
#test
{
    var evaluations = 0
    Debug.safetyBoundCheck(safetyCondition(&evaluations, false), "disabled check")
    Swag.require(evaluations == 0)
}

#[Swag.Safety(.BoundCheck, true)]
#test
{
    var evaluations = 0
    Debug.safetyBoundCheck(safetyCondition(&evaluations, true), "passing check")
    Swag.require(evaluations == 1)
}

#[Swag.Safety(.BoundCheck, true)]
#test
{
    var evaluations = 0
    let failure     = Swag.catchPanic(func|&evaluations|()
    {
        Debug.safetyBoundCheck(safetyCondition(&evaluations, false), "bound check failed")
    })

    Swag.require(failure.raised)
    Swag.require(failure.message() == "bound check failed")
    Swag.require(evaluations == 1)
}
