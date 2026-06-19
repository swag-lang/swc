#global fileprivate

func semaTest001()
{
    switch 1
    {
        default where true:
            break
        default:
            break
    }
}

func semaTest002()
{
    switch 1
    {
        default where false:
            break
        default:
            break
    }
}

func semaTest003()
{
    switch 1
    {
        default where false:
            break
        default where 1 < 2:
            break
    }
}

func semaTest004()
{
    #[Swag.Complete]
    switch 1
    {
        case 1:
            break
        default where false:
            break
    }
}
