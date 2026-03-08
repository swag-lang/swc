#global fileprivate

#test
{
    func nestedReturnChain()->s32
    {
        let start = 3
        {
            let mid = start * 4
            {
                let final = mid + 5
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
        let start = 1
        {
            let add0 = 2
            {
                let add1 = 4
                {
                    let add2 = 8
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
        let first: s8 = 7's8
        {
            let second: u16 = 20'u16
            {
                let third: s32 = cast(s32) first + cast(s32) second
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
            let left = 11
            {
                return left + 1
            }
        }
    }

    func nestedSiblingRight()->s32
    {
        {
            let right = 13
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
        let value = 1
        {
            let value = 2
        }

        return value
    }

    const V = #run nestedRedeclaration()
    #assert(V == 1)
}
