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
    Swag.require(stringEq("toto", "toto"))
    Swag.require(not stringEq("toto", "titi"))
    Swag.require(stringNe("toto", "titi"))
    Swag.require(not stringNe("toto", "toto"))
}
