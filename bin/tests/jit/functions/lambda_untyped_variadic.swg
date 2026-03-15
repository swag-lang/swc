#global fileprivate

alias LambdaUntypedVariadic = func(bool, ...)->s32

func runUntypedVariadicLambda()->s32
{
    let cb: LambdaUntypedVariadic = func(flag, values)->s32
    {
        #assert(#typeof(flag) == bool)
        #assert(#typeof(values[0]) == any)
        #assert(#typeof(values[1]) == any)
        #assert(#typeof(values[2]) == any)

        let text = cast(string) values[2]
        return cast(s32) values[0] + cast(s32) values[1] + cast(s32) text[1] + cast(s32) flag
    }

    return cb(true, 4, 7, "AZ")
}

#test
{
    const result = #run runUntypedVariadicLambda()
    #assert(result == 102)
}
