#global private

#[Swag.NoInline]
func atomGetU8(ptr: *u8)->u8 => Swag.atomget(ptr)

#[Swag.NoInline]
func atomGetU32(ptr: *u32)->u32 => Swag.atomget(ptr)

#[Swag.NoInline]
func atomGetS64(ptr: *s64)->s64 => Swag.atomget(ptr)

// The result is discarded on purpose: the exchange is the effect.
#[Swag.NoInline]
func publishIfZero(ptr: *u32, value: u32)
{
    discard Swag.atomcmpxchg(ptr, 0, value)
}

// Swag.atomget reads the value last stored, at every width
#test
{
    var word = 0x1234'u32
    Swag.assert(atomGetU32(&word) == 0x1234)
    word = 7
    Swag.assert(atomGetU32(&word) == 7)

    var byte = 200'u8
    Swag.assert(atomGetU8(&byte) == 200)

    var wide = -5's64
    Swag.assert(atomGetS64(&wide) == -5)
}

// A compare-exchange whose result is discarded still writes
#test
{
    var flag = 0'u32
    publishIfZero(&flag, 5)
    Swag.assert(flag == 5)
    publishIfZero(&flag, 9)
    Swag.assert(flag == 5)
}

// A polled flag reads its current value on every turn of the loop
#test
{
    var flag  = 0'u32
    var turns = 0
    while Swag.atomget(&flag) == 0
    {
        turns += 1
        if turns == 3 do
            flag = 3
    }

    Swag.assert(turns == 3 and flag == 3)
}
