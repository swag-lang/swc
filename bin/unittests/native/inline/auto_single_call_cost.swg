#global private

func addOne(value: s32)->s32 => value + 1

func autoInlineOnce(value: s32)->s32
{
    var result = value
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    return addOne(result)
}

func recursiveFirst(value: s32)->s32
{
    if value == 0 do
        return 0
    return recursiveSecond(value - 1)
}

func recursiveSecond(value: s32)->s32
{
    if value == 0 do
        return 0
    return recursiveFirst(value - 1)
}

func isPositive(value: s32)->bool => value > 0

func nestedPredicate(value: s32)->bool => isPositive(value)

func earlyReturnThroughNestedCall(value: s32)->s32
{
    if nestedPredicate(value) do
        return 1
    return 2
}

struct CleanupTarget
{
    value: s32
}

impl CleanupTarget
{
    mtd cleanup()
    {
        if nestedPredicate(.value) do
            return
    }
}

func fallibleEarlyReturnThroughNestedCall(value: s32)->s32 fail
{
    var deferred = 0
    defer deferred = value
    var cleanupTarget = CleanupTarget{value}
    defer #fail (&cleanupTarget).cleanup()
    if nestedPredicate(value) do
        return 3
    return 4
}

#test
{
    Swag.assert(autoInlineOnce(21) == 42)
    Swag.assert(recursiveFirst(4) == 0)
    Swag.assert(earlyReturnThroughNestedCall(1) == 1)
    Swag.assert(earlyReturnThroughNestedCall(0) == 2)
    Swag.assert((expect fallibleEarlyReturnThroughNestedCall(1)) == 3)
    Swag.assert((expect fallibleEarlyReturnThroughNestedCall(0)) == 4)
}
