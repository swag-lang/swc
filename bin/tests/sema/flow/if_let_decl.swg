#global fileprivate

#test
{
    if let x = 4 where x > 2
    {
        let y = x
    }
}

#test
{
    if let x = 1 where false
    {
    }
    else
    {
        let y = x
    }
}

#test
{
    if let x = 4 where x > 2 do
        let y = x
}
