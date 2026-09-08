#global private

func invoke(body: func||()) { body() }

func invokePlain(body: func()) { body() }

var plainValue: u32

#test
{
    var value = 0'u32
    let body  = func|&value|()
    {
        defer value += 1
        value += 10
    }
    body()
    Swag.assert(value == 11)
}

// An explicit return and nested scopes must preserve cleanup order after callable conversion.
#test
{
    var value = 0'u32
    invoke(func|&value|()
    {
        defer value = value * 10 + 1
        {
            defer value = value * 10 + 2
            return
        }
    })
    Swag.assert(value == 21)
}

#test
{
    plainValue = 0
    invokePlain(func()
    {
        defer plainValue += 1
        plainValue += 10
    })
    Swag.assert(plainValue == 11)
}

#test
{
    var value = 0'u32
    invoke(func|&value|()
    {
        defer value += 1
        value += 10
    })
    Swag.assert(value == 11)
}
