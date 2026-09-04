#global private

struct DestructAssignDate
{
    year, month, day: u16
}

struct DestructAssignTime
{
    hour, minute, second, millisecond: u16
}

struct DestructAssignDateTime
{
    year, month, day, hour, minute, second, millisecond: u16
}

struct DestructAssignPair
{
    a, b: s32
}

func makeDate()->DestructAssignDate
{
    return {2024, 2, 29}
}

func makeTime()->DestructAssignTime
{
    return {1, 2, 3, 4}
}

func makeDateTime()->DestructAssignDateTime
{
    var result: retval
    {result.year, result.month, result.day} = makeDate()
    {result.hour, result.minute, result.second, result.millisecond} = makeTime()
    return result
}

#test
{
    let value = makeDateTime()
    Swag.assert(value.year == 2024)
    Swag.assert(value.month == 2)
    Swag.assert(value.day == 29)
    Swag.assert(value.hour == 1)
    Swag.assert(value.minute == 2)
    Swag.assert(value.second == 3)
    Swag.assert(value.millisecond == 4)
}

#test
{
    var pair = DestructAssignPair{1, 2}
    {pair.b, pair.a} = pair
    Swag.assert(pair.a == 2)
    Swag.assert(pair.b == 1)

    var other = DestructAssignPair{0, 0}
    {other.a, ?} = pair
    Swag.assert(other.a == 2)
    Swag.assert(other.b == 0)
}
