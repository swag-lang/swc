#global fileprivate

struct ShadowItem
{
    count: s32
}

func set()->ShadowItem { return {count: -1} }
func score()->s32 { return 30 }
func entry()->s32 { return 100 }

#[Swag.Macro]
func injectPlain(stmt: #code void)
{
    #inject(stmt)
}

func semaTest001()
{
    injectPlain()
    {
        let set: ShadowItem = {count: 3}
        let count = set.count
        #assert(#typeof(count) == s32)
    }
}

func semaTest002()
{
    injectPlain()
    {
        let before = score()
        let score = 12
        let total = before + score
        #assert(#typeof(total) == s32)
    }
}

func semaTest003()
{
    injectPlain()
    {
        {
            let set: ShadowItem = {count: 6}
            let count = set.count
            #assert(#typeof(count) == s32)
        }

        let item = set()
        let count = item.count
        #assert(#typeof(count) == s32)
    }
}

func semaTest004()
{
    injectPlain()
    {
        let values = [1, 2, 3]
        foreach entry in values
        {
            let value = entry + 1
            #assert(#typeof(value) == s32)
        }

        let fallback = entry()
        #assert(#typeof(fallback) == s32)
    }
}

func semaTest005()
{
    injectPlain()
    {
        let result = lateMacroHelper()
        #assert(#typeof(result) == s32)
    }
}

func lateMacroHelper()->s32 { return 27 }
