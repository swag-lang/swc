#global fileprivate // swc-option suite-test

enum Color {
    Red,
    Green,
    Blue
}

#test
{
    var c = Color.Green
    #[Swag.Complete]
    switch (c)
    {
        case Color.Red:
            break
        case Color.Green:
            break
        case Color.Blue:
            break
    }
}

#test
{
    var c = Color.Red
    #[Swag.Complete]
    switch (c)
    {
        case Color.Blue:
            break
        case Color.Red:
            break
        case Color.Green:
            break
    }
}

