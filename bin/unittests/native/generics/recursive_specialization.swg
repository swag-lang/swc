#global private

func(T) roundTrip(value: T)->s32
{
    #static if T == s32
    {
        return roundTrip'f64(cast(f64) value)
    }
    else
    {
        return cast(s32) value
    }
}

#test
{
    Swag.assert(roundTrip(42) == 42)
    Swag.assert(roundTrip(-17) == -17)
}
