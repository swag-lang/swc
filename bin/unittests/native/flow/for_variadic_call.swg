#global private

func touch(_: ...)->u32
{
    return 1
}

#test
{
    var count: s32 = 0
    for i in 1 to 5 do
        count += cast(s32, touch(i, " "))

    Swag.require(count == 5)
}
