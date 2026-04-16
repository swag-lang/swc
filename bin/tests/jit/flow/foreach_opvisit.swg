#global fileprivate

struct JitFieldVisits
{
    x: s32 = 10
    y: s32 = 20
    z: s32 = 30
}

impl JitFieldVisits
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisit(me, stmt: #code void)
    {
        #if ptr do
            #error("JitFieldVisits does not expose pointer iteration.")

        #if back
        {
            for idx in 3
            {
                #macro
                {
                    var #alias0: s32 = undefined
                    switch #up idx
                    {
                    case 0: #alias0 = #up me.z
                    case 1: #alias0 = #up me.y
                    case 2: #alias0 = #up me.x
                    }

                    let #alias1 = @index
                    #inject(#up stmt)
                }
            }

            return
        }

        for idx in 3
        {
            #macro
            {
                var #alias0: s32 = undefined
                switch #up idx
                {
                case 0: #alias0 = #up me.x
                case 1: #alias0 = #up me.y
                case 2: #alias0 = #up me.z
                }

                let #alias1 = @index
                #inject(#up stmt)
            }
        }
    }
}

struct JitBufferVisits
{
    values: [3] s32 = [3, 6, 9]
}

impl JitBufferVisits
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisit(me, stmt: #code void)
    {
        #if back
        {
            #if ptr
            {
                for idx in 3
                {
                    #macro
                    {
                        var #alias0: *s32 = cast(*s32) &(#up me.values[2 - #up idx])
                        let #alias1 = @index
                        #inject(#up stmt)
                    }
                }
            }
            #else
            {
                for idx in 3
                {
                    #macro
                    {
                        let #alias0 = #up me.values[2 - #up idx]
                        let #alias1 = @index
                        #inject(#up stmt)
                    }
                }
            }
        }
        #else
        {
            #if ptr
            {
                for idx in 3
                {
                    #macro
                    {
                        var #alias0: *s32 = cast(*s32) &(#up me.values[#up idx])
                        let #alias1 = @index
                        #inject(#up stmt)
                    }
                }
            }
            #else
            {
                for idx in 3
                {
                    #macro
                    {
                        let #alias0 = #up me.values[#up idx]
                        let #alias1 = @index
                        #inject(#up stmt)
                    }
                }
            }
        }
    }
}

struct JitReverseVisits
{
    values: [3] s32 = [1, 2, 3]
}

impl JitReverseVisits
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisit(const me, stmt: #code void)
    {
        #if ptr do
            #error("JitReverseVisits does not expose pointer iteration.")

        #if back do
            #error("reverse iteration must use opVisitReverse")

        for idx in 3
        {
            #macro
            {
                let #alias0 = #up me.values[#up idx]
                let #alias1 = @index
                #inject(#up stmt)
            }
        }
    }

    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisitReverse(const me, stmt: #code void)
    {
        #if ptr do
            #error("JitReverseVisits does not expose pointer iteration.")

        for idx in 3
        {
            #macro
            {
                let #alias0 = #up me.values[2 - #up idx]
                let #alias1 = @index
                #inject(#up stmt)
            }
        }
    }
}

struct JitHiddenAliasVisits
{
    values: [3] s32 = [4, 5, 6]
}

struct JitFieldPointerVisits
{
    first:  s32 = 1
    second: s32 = 2
    third:  s32 = 3
}

struct JitPairVisits
{
    values: [4] s32 = [2, 4, 6, 8]
}

struct JitConstPointerVisits
{
    values: [3] s32 = [7, 8, 9]
}

impl JitHiddenAliasVisits
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisit(const me, stmt: #code void)
    {
        #if ptr do
            #error("JitHiddenAliasVisits does not expose pointer iteration.")

        #if back do
            #error("JitHiddenAliasVisits does not expose reverse iteration.")

        for idx in 3
        {
            #macro
            {
                let #alias0 = #up me.values[#up idx]
                let #alias1 = #up me.values[#up idx] * 10
                let #alias2 = @index
                #inject(#up stmt)
            }
        }
    }
}

impl JitFieldPointerVisits
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisit(me, stmt: #code void)
    {
        #if back do
            #error("JitFieldPointerVisits does not expose reverse iteration.")

        #if ptr
        {
            #macro
            {
                var #alias0: *s32 = cast(*s32) &(#up me.first)
                let #alias1 = 0'u64
                #inject(#up stmt)
            }

            #macro
            {
                var #alias0: *s32 = cast(*s32) &(#up me.second)
                let #alias1 = 1'u64
                #inject(#up stmt)
            }

            #macro
            {
                var #alias0: *s32 = cast(*s32) &(#up me.third)
                let #alias1 = 2'u64
                #inject(#up stmt)
            }
        }
        #else
        {
            for idx in 3
            {
                #macro
                {
                    var #alias0: s32 = undefined
                    switch #up idx
                    {
                    case 0: #alias0 = #up me.first
                    case 1: #alias0 = #up me.second
                    case 2: #alias0 = #up me.third
                    }

                    let #alias1 = @index
                    #inject(#up stmt)
                }
            }
        }
    }
}

impl JitPairVisits
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisitPairs(const me, stmt: #code void)
    {
        #if ptr do
            #error("JitPairVisits does not expose pointer iteration.")

        #if back
        {
            for idx in 3
            {
                #macro
                {
                    let #alias0 = #up me.values[2 - #up idx]
                    let #alias1 = #up me.values[3 - #up idx]
                    #inject(#up stmt)
                }
            }

            return
        }

        for idx in 3
        {
            #macro
            {
                let #alias0 = #up me.values[#up idx]
                let #alias1 = #up me.values[#up idx + 1]
                #inject(#up stmt)
            }
        }
    }
}

impl JitConstPointerVisits
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisit(const me, stmt: #code void)
    {
        #if back do
            #error("JitConstPointerVisits does not expose reverse iteration.")

        #if ptr
        {
            for idx in 3
            {
                #macro
                {
                    var #alias0: const *s32 = cast(const *s32) &(#up me.values[#up idx])
                    let #alias1 = @index
                    #inject(#up stmt)
                }
            }
        }
        #else
        {
            for idx in 3
            {
                #macro
                {
                    let #alias0 = #up me.values[#up idx]
                    let #alias1 = @index
                    #inject(#up stmt)
                }
            }
        }
    }
}

func jitForeachVisitForward()->s32
{
    var values = JitFieldVisits{}
    var acc: s32

    foreach value, index in values do
        acc += value + cast(s32) index

    return acc
}

func jitForeachVisitWhere()->s32
{
    var values = JitBufferVisits{}
    var acc: s32

    foreach value, ordinal in values where value != 6
    {
        if ordinal == 0 do
            continue

        acc += value + cast(s32) ordinal
        break
    }

    return acc
}

func jitForeachVisitByAddress()->s32
{
    var values = JitBufferVisits{}

    foreach &value, ordinal in values do
        dref value += cast(s32) (ordinal + 1)

    return values.values[0] + values.values[1] + values.values[2]
}

#test
{
    const V = #run jitForeachVisitForward()
    #assert(V == 63)
}

#test
{
    const V = #run jitForeachVisitWhere()
    #assert(V == 11)
}

#test
{
    const V = #run jitForeachVisitByAddress()
    #assert(V == 24)
}
