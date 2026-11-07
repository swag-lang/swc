#global private

#[Swag.NoInline]
func atomGetU8(ptr: *u8)->u8 => Swag.atomicLoad(ptr)

#[Swag.NoInline]
func atomGetU32(ptr: *u32)->u32 => Swag.atomicLoad(ptr)

#[Swag.NoInline]
func atomGetS64(ptr: *s64)->s64 => Swag.atomicLoad(ptr)

// The result is discarded on purpose: the exchange is the effect.
#[Swag.NoInline]
func publishIfZero(ptr: *u32, value: u32)
{
    discard Swag.atomicCompareExchange(ptr, 0, value)
}

// Swag.atomicLoad reads the value last stored, at every width
#test
{
    var word = 0x1234'u32
    Swag.require(atomGetU32(&word) == 0x1234)
    word = 7
    Swag.require(atomGetU32(&word) == 7)

    var byte = 200'u8
    Swag.require(atomGetU8(&byte) == 200)

    var wide = -5's64
    Swag.require(atomGetS64(&wide) == -5)
}

// A compare-exchange whose result is discarded still writes
#test
{
    var flag = 0'u32
    publishIfZero(&flag, 5)
    Swag.require(flag == 5)
    publishIfZero(&flag, 9)
    Swag.require(flag == 5)
}

// A polled flag reads its current value on every turn of the loop
#test
{
    var flag  = 0'u32
    var turns = 0
    while Swag.atomicLoad(&flag) == 0
    {
        turns += 1
        if turns == 3 do
            flag = 3
    }

    Swag.require(turns == 3 and flag == 3)
}

// A Boolean context tests the full atomic integer, including bits above the low byte.
#test
{
    var flag = 0x100'u32
    let isClear = func|flag = &flag|()->bool => not Swag.atomicLoad(flag)

    Swag.require(not isClear())
    flag = 0
    Swag.require(isClear())
    flag = 1
    Swag.require(not isClear())

    let waitForFlag = func|flag = &flag|()->u32
    {
        var turns = 0'u32
        while not Swag.atomicLoad(flag)
        {
            turns += 1
            if turns == 3 do break
            Swag.atomicStore(flag, 0x100'u32)
        }
        return turns
    }

    flag = 0
    Swag.require(waitForFlag() == 1)
}
