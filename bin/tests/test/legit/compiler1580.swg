// swc-option suite-test

#global fileprivate
#global skip
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

func toto() {}

#test toto()
