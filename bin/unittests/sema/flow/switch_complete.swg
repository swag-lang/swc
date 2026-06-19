#global fileprivate

enum Color {
    Red,
    Green,
    Blue
}

func semaTest001()
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

func semaTest002()
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
