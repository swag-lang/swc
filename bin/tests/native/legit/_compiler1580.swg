// 

#global fileprivate
#test
{
    enum Color
    {
        Red
        Green
        Blue
    }

    let a = Color.Green
    @assert(a == 1)
}

func toto()->bool { return true }

#test
{
    @assert(toto())
}

