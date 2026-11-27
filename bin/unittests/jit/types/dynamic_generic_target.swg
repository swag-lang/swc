#global private

func(T) extract(source: any)->T => assume cast (T, source)

#[Swag.Inline]
func(T) extractInline(source: any)->T => assume cast (T, source)

#test
{
    var value: any = 42_s32
    Swag.require(extract!{s32}(value) == 42)
    Swag.require(extractInline!{s32}(value) == 42)
    value = "generic"
    Swag.require(extract!{string}(value) == "generic")
    Swag.require(extractInline!{string}(value) == "generic")
}

#[Swag.Inline]
func capturedPack(values: any...)->s32
{
    let read = func|values|()->s32
    {
        return assume cast (s32, values[0]) + assume cast (s32, values[1])
    }
    return read()
}

#test
{
    Swag.require(capturedPack(7_s32, 8_s32) == 15)
}
