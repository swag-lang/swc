// 

#global private

func stringEq(a: string, b: string)->bool
{
    return a == b
}

func stringNe(a: string, b: string)->bool
{
    return a != b
}

#test
{
    Swag.assert(stringEq("toto", "toto"))
    Swag.assert(!stringEq("toto", "titi"))
    Swag.assert(stringNe("toto", "titi"))
    Swag.assert(!stringNe("toto", "toto"))
}
