#init
{
    Counter = 2
}

#premain
{
    Counter += 1
}

// Arithmetic helpers and init/premain counter
#test
{
    var a = 0
    a += 4
    check(add(a, 5) == 9, 1)
    check(Counter == 3, 2)
    Swag.require(add(a, 5) == 9)
    Swag.require(Counter == 3)
    check(touch(4) == 7, 3)
    Counter = 3
    Swag.require(touch(4) == 7)
}

// Triple, square_plus_seed, and counter state
#test
{
    check(triple(4) == 12, 4)
    check(square_plus_seed(5) == 32, 5)
    check(Counter == 3 or Counter == 7, 6)
    Swag.require(triple(4) == 12)
    Swag.require(square_plus_seed(5) == 32)
    Swag.require(Counter == 3 or Counter == 7)
}

// Pointer delta and int-from-float subtraction
#test
{
    check(pointer_step_delta() == 1, 8)
    check(subtract_int_from_float(10.5, 2) == 8.5, 9)
    Swag.require(pointer_step_delta() == 1)
    Swag.require(subtract_int_from_float(10.5, 2) == 8.5)
}

#main
{}

#drop
{
    DropCheck = Counter + Seed
    if DropCheck != 10 and DropCheck != 14
    {
        fault(7)
    }
}
