#global private

func semaTest001()
{
    if let x = 4 where x > 2
    {
        let y = x
        discard y
    }
}

func semaTest002()
{
    if let x = 1 where false {}
    else
    {
        let y = x
        discard y
    }
}

func semaTest003()
{
    if let x = 4 where x > 2
    {
        let y = x
        discard y
    }
}
