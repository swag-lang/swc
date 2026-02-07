#global internal

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
    var c = Color.Green
    #[Swag.Complete]
    switch (c) // swc-expected-error {{sema_err_switch_complete_enum_not_exhaustive}}
    {
        case Color.Red:
            break
        case Color.Green:
            break
    }
}
