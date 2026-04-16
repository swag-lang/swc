#global fileprivate

alias FieldAlias = FieldVisits

struct FieldVisits
{
    x: s32 = 10
    y: s32 = 20
    z: s32 = 30
}

impl FieldVisits
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisit(me, stmt: #code void)
    {
        #if ptr do
            #error("FieldVisits does not expose pointer iteration.")

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

struct BufferVisits
{
    values: [3] s32 = [3, 6, 9]
}

impl BufferVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) opVisit(stmt: #code void)
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

struct ReverseVisits
{
    values: [3] s32 = [1, 2, 3]
}

impl ReverseVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code void)
    {
        #if ptr do
            #error("ReverseVisits does not expose pointer iteration.")

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
    mtd(ptr: bool, back: bool) const opVisitReverse(stmt: #code void)
    {
        #if ptr do
            #error("ReverseVisits does not expose pointer iteration.")

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

struct HiddenAliasVisits
{
    values: [3] s32 = [4, 5, 6]
}

struct FieldPointerVisits
{
    first:  s32 = 1
    second: s32 = 2
    third:  s32 = 3
}

struct PairVisits
{
    values: [4] s32 = [2, 4, 6, 8]
}

struct ConstPointerVisits
{
    values: [3] s32 = [7, 8, 9]
}

impl HiddenAliasVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code void)
    {
        #if ptr do
            #error("HiddenAliasVisits does not expose pointer iteration.")

        #if back do
            #error("HiddenAliasVisits does not expose reverse iteration.")

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

impl FieldPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) opVisit(stmt: #code void)
    {
        #if back do
            #error("FieldPointerVisits does not expose reverse iteration.")

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

impl PairVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisitPairs(stmt: #code void)
    {
        #if ptr do
            #error("PairVisits does not expose pointer iteration.")

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

impl ConstPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code void)
    {
        #if back do
            #error("ConstPointerVisits does not expose reverse iteration.")

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

#test
{
    var values: FieldAlias
    var sumValues = 0
    var sumIndexes: u64

    foreach value, index in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(index) == #typeof(@index))
        sumValues += value
        sumIndexes += index
    }

    @assert(sumValues == 60)
    @assert(sumIndexes == 3)
}

#test
{
    var values = BufferVisits{}
    var acc = 0

    foreach value, ordinal in values where value != 6
    {
        if ordinal == 0 do
            continue

        acc += value + cast(s32) ordinal
        break
    }

    @assert(acc == 11)
}

#test
{
    var values = BufferVisits{}

    foreach &value, ordinal in values do
        dref value += cast(s32) (ordinal + 1)

    @assert(values.values[0] == 4)
    @assert(values.values[1] == 8)
    @assert(values.values[2] == 12)
}

#test
{
    var values = ReverseVisits{}
    var code = 0
    var order: u64

    foreach #reverse value, index in values
    {
        code = code * 10 + value
        order += index
    }

    @assert(code == 321)
    @assert(order == 3)
}

#test
{
    var values = ReverseVisits{}
    var code = 0

    foreach #Reverse value, index in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(index) == #typeof(@index))
        code = code * 10 + value + cast(s32) index - cast(s32) index
    }

    @assert(code == 321)
}

#test
{
    var values = HiddenAliasVisits{}
    var count: u64
    var sum = 0

    foreach values
    {
        count += 1
        sum += cast(s32) @index
    }

    @assert(count == 3)
    @assert(sum == 3)
}

#test
{
    var values = HiddenAliasVisits{}
    var code = 0
    var order: u64

    foreach value in values
    {
        #assert(#typeof(value) == s32)
        code = code * 10 + value
        order += @index
    }

    @assert(code == 456)
    @assert(order == 3)
}

#test
{
    var values = HiddenAliasVisits{}
    var sum = 0

    foreach value, scaled in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(scaled) == s32)
        sum += value + scaled + cast(s32) @index
    }

    @assert(sum == 168)
}

#test
{
    var values = FieldPointerVisits{}
    var mutatedSum = 0

    foreach &value, ordinal in values
    {
        #assert(#typeof(value) == *s32)
        dref value += cast(s32) (ordinal + 1)
        mutatedSum += dref value
    }

    @assert(values.first == 2)
    @assert(values.second == 4)
    @assert(values.third == 6)
    @assert(mutatedSum == 12)
}

#test
{
    var values = PairVisits{}
    var signature = 0
    var order: u64

    foreach #Pairs left, right in values
    {
        #assert(#typeof(left) == s32)
        #assert(#typeof(right) == s32)
        signature = signature * 100 + left * 10 + right
        order += @index
    }

    @assert(signature == 244668)
    @assert(order == 3)
}

#test
{
    let values = ConstPointerVisits{}
    var sum = 0

    foreach &value, ordinal in values
    {
        #assert(#typeof(value) == const *s32)
        sum += dref value + cast(s32) ordinal
    }

    @assert(sum == 27)
}
