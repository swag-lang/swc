#global internal

#test
{
    func nestedReturnChain()->s32
    {
        var start = 3
        {
            var mid = start * 4
            {
                var final = mid + 5
                return final
            }
        }
    }

    const V = #run nestedReturnChain()
    #assert(V == 17)
}

#test
{
    func nestedReturnSum()->s32
    {
        var start = 1
        {
            var add0 = 2
            {
                var add1 = 4
                {
                    var add2 = 8
                    return start + add0 + add1 + add2
                }
            }
        }
    }

    const V = #run nestedReturnSum()
    #assert(V == 15)
}

#test
{
    func nestedTypedLocals()->s32
    {
        var first: s8 = 7's8
        {
            var second: u16 = 20'u16
            {
                var third: s32 = cast(s32) first + cast(s32) second
                return third
            }
        }
    }

    const V = #run nestedTypedLocals()
    #assert(V == 27)
}

#test
{
    func nestedSiblingLeft()->s32
    {
        {
            var left = 11
            {
                return left + 1
            }
        }
    }

    func nestedSiblingRight()->s32
    {
        {
            var right = 13
            {
                return right + 2
            }
        }
    }

    const V0 = #run nestedSiblingLeft()
    const V1 = #run nestedSiblingRight()
    #assert(V0 == 12)
    #assert(V1 == 15)
}

#test
{
    func nestedRedeclaration()->s32
    {
        var value = 1
        {
            var value = 2 // swc-expected-error {{sema_err_already_defined}}
        }

        return value
    }

    const V = #run nestedRedeclaration()
}
