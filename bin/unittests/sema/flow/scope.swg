#global private

func semaTest001()
{
    #scope(Outer)
    {
        for 10
        {
            break to Outer
        }
    }
}

func semaTest002()
{
    #scope(Outer)
    for 10
    {
        break to Outer
    }
}

func semaTest003()
{
    #scope(A)
    {
        #scope(A)
        {
            break to A
        }

        break to A
    }
}

func semaTest004()
{
    #scope(Loop)
    {
        continue
        break
    }
}
