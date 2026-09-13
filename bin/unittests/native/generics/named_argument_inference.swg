#global private

func(T) pair(first: T, second: T)->T => first * 10 + second
func(T) triple(first: T, second: T, third: T)->T => first * 100 + second * 10 + third
func(T) apply(value: T, callback: func(T)->T)->T => callback(value)

#test
{
    Swag.assert(pair(second: 2's32, first: 1) == 12)
    Swag.assert(pair(first: 1's32, second: 2) == 12)
    Swag.assert(pair'(s32)(second: 2, first: 1) == 12)
}

#test
{
    Swag.assert(triple(1's32, third: 3, second: 2) == 123)
}

#test
{
    let receiver = 1's32
    Swag.assert(receiver.pair(second: 2) == 12)
    Swag.assert(receiver.triple(third: 3, second: 2) == 123)
    Swag.assert(receiver.triple(2, third: 3) == 123)
}

#test
{
    Swag.assert(pair((1's32), (2's32)) == 12)
    Swag.assert(pair(second: (2's32), first: (1's32)) == 12)
}

#test
{
    Swag.assert(apply(value: 3's32, callback: func(x) => x * 2) == 6)
    Swag.assert(apply(4's32, callback: (func(x) => x * 2)) == 8)
}
