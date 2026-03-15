#global fileprivate // swc-option suite-test

enum Color {
    Red,
    Green,
    Blue
}

#test
{
    var c = Color.Green
    var hit = 0
    #[Swag.Complete]
    switch (c)
    {
        case Color.Red:
            hit = 1
            break
        case Color.Green:
            hit = 2
            break
        case Color.Blue:
            hit = 3
            break
    }
    @assert(hit == 2)
}

#test
{
    var c = Color.Red
    var hit = 0
    #[Swag.Complete]
    switch (c)
    {
        case Color.Blue:
            hit = 1
            break
        case Color.Red:
            hit = 2
            break
        case Color.Green:
            hit = 3
            break
    }
    @assert(hit == 2)
}

