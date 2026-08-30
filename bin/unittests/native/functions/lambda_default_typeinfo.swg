#global private

func lambdaDefaultTypeInfoFunc0()->s32             => 1
func lambdaDefaultTypeInfoFunc1(value: bool)->bool => value

alias LambdaDefaultTypeInfoFn = func(info = #typeof(lambdaDefaultTypeInfoFunc0))->u64

#test
{
    let cb: LambdaDefaultTypeInfoFn = func(info)->u64
    {
        #assert(#typeof(info) == const *TypeInfoFunc)
        return cast(u64) info.parameters.count
    }

    Swag.assert(cb() == 0)
    Swag.assert(cb(#typeof(lambdaDefaultTypeInfoFunc1)) == 1)
}
