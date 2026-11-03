#global private

func(T) pair(first: T, second: T)->T             => first * 10 + second
func(T) triple(first: T, second: T, third: T)->T => first * 100 + second * 10 + third
func(T) apply(value: T, callback: func(T)->T)->T => callback(value)
func(T) choose(first: T, second: T)->T           => first * 10 + second
func choose(value: s32, extra: s32)->s32         => value + extra

#test
{
    Swag.require(pair(second: 2's32, first: 1) == 12)
    Swag.require(pair(first: 1's32, second: 2) == 12)
    Swag.require(pair'(s32)(second: 2, first: 1) == 12)
}

#test
{
    Swag.require(triple(1's32, third: 3, second: 2) == 123)
}

#test
{
    let receiver = 1's32
    Swag.require(receiver.pair(second: 2) == 12)
    Swag.require(receiver.triple(third: 3, second: 2) == 123)
    Swag.require(receiver.triple(2, third: 3) == 123)
}

#test
{
    Swag.require(pair((1's32), (2's32)) == 12)
    Swag.require(pair(second: (2's32), first: (1's32)) == 12)
}

#test
{
    Swag.require(apply(value: 3's32, callback: func(x) => x * 2) == 6)
    Swag.require(apply(4's32, callback: (func(x) => x * 2)) == 8)
}

#test
{
    // Rejecting a generic candidate's argument names must leave other overloads available.
    Swag.require(choose(value: 3, extra: 4) == 7)
    Swag.require(choose(second: 4's32, first: 3) == 34)
}
