#global fileprivate

#test
{
    switch 1
    {
        default where true:
            break
        default:
            break
    }
}

#test
{
    switch 1
    {
        default where false:
            break
        default:
            break
    }
}

#test
{
    switch 1
    {
        default where false:
            break
        default where 1 < 2:
            break
    }
}

#test
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
