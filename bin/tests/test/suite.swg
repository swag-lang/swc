#init
{
    Counter = 2
}

#premain
{
    Counter += 1
}

#test
{
    check(add(4, 5) == 9, 1)
    check(Counter == 3, 2)
    check(touch(4) == 7, 3)
}

#test
{
    check(triple(4) == 12, 4)
    check(square_plus_seed(5) == 32, 5)
    check(Counter == 7, 6)
}

#test
{
    check(pointer_step_delta() == 1, 8)
    check(subtract_int_from_float(10.5, 2) == 8.5, 9)
}

#drop
{
    DropCheck = Counter + Seed
    if DropCheck != 14
    {
        fail(7)
    }
}
