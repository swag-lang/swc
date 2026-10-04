#global private

struct ShadowItem
{
    count: s32
}

func set()->ShadowItem { return {count: -1} }
func score()->s32 { return 30 }
func entry()->s32 { return 100 }

const shadowConst = 97

#[Swag.NoInline]
func readShadowValue(value: s32)->s32 => value

#[Swag.Macro]
func injectPlain(stmt: #code)
{
    #inject(stmt)
}

#test
{
    var result = 0
    injectPlain()
    {
        let set: ShadowItem = {count: 3}
        result = set.count
    }

    Swag.assert(result == 3)
}

#test
{
    var result = 0
    injectPlain()
    {
        let before = score()
        let score  = 12
        result = before + score
    }

    Swag.assert(result == 42)
}

#test
{
    var result = 0
    injectPlain()
    {
        {
            let set: ShadowItem = {count: 6}
            result += set.count
        }

        result += set().count
    }

    Swag.assert(result == 5)
}

#test
{
    var result = 0
    injectPlain()
    {
        let values = [1, 2, 3]
        for entry in values
        {
            result += entry
        }

        result += entry()
    }

    Swag.assert(result == 106)
}

// A caller constant must not bypass the local shadow check when the injected
// block is resolved. Reads before and after the nested scope keep the caller value.
#test
{
    var result = 0
    injectPlain()
    {
        let before = shadowConst
        {
            let shadowConst = readShadowValue(3)
            result += 2 * shadowConst
        }
        result += before + shadowConst
    }

    Swag.assert(result == 200)
}

// The same lookup rule applies when a caller's let has a folded constant value.
#test
{
    let shadowLet = 101
    var result    = 0
    injectPlain()
    {
        let before = shadowLet
        {
            let shadowLet = readShadowValue(4)
            result += 2 * shadowLet
        }
        result += before + shadowLet
    }

    Swag.assert(result == 210)
}
