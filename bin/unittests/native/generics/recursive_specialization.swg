#global private

func(T) roundTrip(value: T)->s32
{
    #static if T == s32
    {
        return roundTrip'f64(cast(f64, value))
    }
    else
    {
        return cast(s32, value)
    }
}

#test
{
    Swag.require(roundTrip(42) == 42)
    Swag.require(roundTrip(-17) == -17)
}
