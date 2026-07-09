#global private

struct ShadowItem
{
    count: s32
}

func set()->ShadowItem { return {count: -1} }
func score()->s32 { return 30 }
func entry()->s32 { return 100 }

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

    @assert(result == 3)
}

#test
{
    var result = 0
    injectPlain()
    {
        let before = score()
        let score = 12
        result = before + score
    }

    @assert(result == 42)
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

    @assert(result == 5)
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

    @assert(result == 106)
}
