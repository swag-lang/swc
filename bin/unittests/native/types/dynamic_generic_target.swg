#global private

func(T) extract(source: any)->T => cast #assume (T) source

#[Swag.Inline]
func(T) extractInline(source: any)->T => cast #assume (T) source

#test
{
    var value: any = 42's32
    Swag.assert(extract's32(value) == 42)
    Swag.assert(extractInline's32(value) == 42)
    value = "generic"
    Swag.assert(extract'string(value) == "generic")
    Swag.assert(extractInline'string(value) == "generic")
}

#[Swag.Inline]
func capturedPack(values: any...)->s32
{
    let read = func|values|()->s32
    {
        return cast #assume (s32) values[0] + cast #assume (s32) values[1]
    }
    return read()
}

#test
{
    Swag.assert(capturedPack(7's32, 8's32) == 15)
}
