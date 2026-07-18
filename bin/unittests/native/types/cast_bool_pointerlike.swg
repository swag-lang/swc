#global private
#global #[Swag.ExplicitNullability]

func stringToBool()->bool
{
    let empty = cast(#null string) null
    let text: #nonull string = "x"
    return !cast(bool) empty and cast(bool) text
}

func sliceToBool()->bool
{
    let empty = cast(#null [..] s32) null
    var data: [2] s32 = [1, 2]
    let values = cast(#nonull [..] s32) data
    return !cast(bool) empty and cast(bool) values
}

#test
{
    @assert(stringToBool())
    @assert(sliceToBool())
}
