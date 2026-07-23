#global private

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
    func(ptr: bool, back: bool) opVisit(me, stmt: #code(item: s32, index))
    {
        #if ptr do
            #error("FieldVisits does not expose pointer iteration.")

        #if back
        {
            for idx in 3
            {
                var visitItem: s32 = undefined
                switch idx
                {
                case 0: visitItem = me.z
                case 1: visitItem = me.y
                default: visitItem = me.x
                }

                #inject(stmt, item = visitItem, index = @index)
            }

            return
        }

        for idx in 3
        {
            var visitItem: s32 = undefined
            switch idx
            {
            case 0: visitItem = me.x
            case 1: visitItem = me.y
            default: visitItem = me.z
            }

            #inject(stmt, item = visitItem, index = @index)
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
    mtd(ptr: bool, back: bool) opVisit(stmt: #code(item, index))
    {
        #if back
        {
            #if ptr
            {
                for idx in 3
                {
                    #inject(stmt, item = cast(&s32) &(me.values[2 - idx]), index = @index)
                }
            }
                #else
            {
                for idx in 3
                {
                    #inject(stmt, item = me.values[2 - idx], index = @index)
                }
            }
        }
            #else
        {
            #if ptr
            {
                for idx in 3
                {
                    #inject(stmt, item = cast(&s32) &(me.values[idx]), index = @index)
                }
            }
                #else
            {
                for idx in 3
                {
                    #inject(stmt, item = me.values[idx], index = @index)
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
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: s32, index))
    {
        #if ptr do
            #error("ReverseVisits does not expose pointer iteration.")

        #if back do
            #error("reverse iteration must use opVisitReverse")

        for idx in 3
        {
            #inject(stmt, item = me.values[idx], index = @index)
        }
    }

    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisitReverse(stmt: #code(item: s32, index))
    {
        #if ptr do
            #error("ReverseVisits does not expose pointer iteration.")

        for idx in 3
        {
            #inject(stmt, item = me.values[2 - idx], index = @index)
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

struct ReturnVisits
{
    values: [3] s32 = [4, 5, 6]
}

impl HiddenAliasVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: s32, tens: s32, index))
    {
        #if ptr do
            #error("HiddenAliasVisits does not expose pointer iteration.")

        #if back do
            #error("HiddenAliasVisits does not expose reverse iteration.")

        for idx in 3
        {
            #inject(stmt, item = me.values[idx], tens = me.values[idx] * 10, index = @index)
        }
    }
}

impl FieldPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) opVisit(stmt: #code(item, index))
    {
        #if back do
            #error("FieldPointerVisits does not expose reverse iteration.")

        #if ptr
        {
            #inject(stmt, item = cast(&s32) &(me.first), index = 0'u64)
            #inject(stmt, item = cast(&s32) &(me.second), index = 1'u64)
            #inject(stmt, item = cast(&s32) &(me.third), index = 2'u64)
        }
            #else
        {
            for idx in 3
            {
                var visitItem: s32 = undefined
                switch idx
                {
                case 0: visitItem = me.first
                case 1: visitItem = me.second
                case 2: visitItem = me.third
                }

                #inject(stmt, item = visitItem, index = @index)
            }
        }
    }
}

impl PairVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisitPairs(stmt: #code(left: s32, right: s32))
    {
        #if ptr do
            #error("PairVisits does not expose pointer iteration.")

        #if back
        {
            for idx in 3
            {
                #inject(stmt, left = me.values[2 - idx], right = me.values[3 - idx])
            }

            return
        }

        for idx in 3
        {
            #inject(stmt, left = me.values[idx], right = me.values[idx + 1])
        }
    }
}

impl ConstPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item, index))
    {
        #if back do
            #error("ConstPointerVisits does not expose reverse iteration.")

        #if ptr
        {
            for idx in 3
            {
                #inject(stmt, item = cast(const &s32) &(me.values[idx]), index = @index)
            }
        }
            #else
        {
            for idx in 3
            {
                #inject(stmt, item = me.values[idx], index = @index)
            }
        }
    }
}

impl ReturnVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: s32))
    {
        #if ptr do
            #error("ReturnVisits does not expose pointer iteration.")

        if !@countof(.values) do
            return

        var remain = @countof(.values)
        #scope(Up)
            for idx in @countof(.values)
        {
            #scope(Down)
            {
                #inject(stmt, item = me.values[idx], break = break to Up, continue = break to Down)
            }

            remain -= 1
            if !remain do
                break
        }
    }
}

func nativeForeachVisitReturn()->bool
{
    var values = ReturnVisits{}

    for value in values
    {
        if value == 6 do
            return true
    }

    return false
}

struct(T) GenericScopedVisits
{
    const FIRST = 1'u64
    values: [3] T
}

impl GenericScopedVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item, index))
    {
        #if ptr do
            #error("GenericScopedVisits does not expose pointer iteration.")

        #if back do
            #error("GenericScopedVisits does not expose reverse iteration.")

        #scope(Outer)
            for 3
        {
            if @index < GenericScopedVisits.FIRST do
                continue

            #scope(Inner)
            {
                #inject(stmt, item = me.values[@index], index = @index, break = break to Outer, continue = break to Inner)
            }
        }
    }
}

#test
{
    var values: FieldAlias
    var sumValues = 0
    var sumIndexes: u64

    for value, index in values
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

    for value, ordinal in values where value != 6
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

    for &value, ordinal in values do
        value += cast(s32) (ordinal + 1)

    @assert(values.values[0] == 4)
    @assert(values.values[1] == 8)
    @assert(values.values[2] == 12)
}

#test
{
    var values = ReverseVisits{}
    var code = 0
    var order: u64

    for #reverse value, index in values
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

    for #Reverse value, index in values
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

    for value in values
    {
        count += 1
        sum += cast(s32) @index
        discard value
    }

    @assert(count == 3)
    @assert(sum == 3)
}

#test
{
    var values = HiddenAliasVisits{}
    var code = 0
    var order: u64

    for value in values
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

    for value, scaled in values
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

    for &value, ordinal in values
    {
        #assert(#typeof(value) == #type &s32)
        value += cast(s32) (ordinal + 1)
        mutatedSum += value
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

    for #Pairs left, right in values
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

    for &value, ordinal in values
    {
        #assert(#typeof(value) == #type const &s32)
        sum += value + cast(s32) ordinal
    }

    @assert(sum == 27)
}

#test
{
    @assert(nativeForeachVisitReturn())
}

#test
{
    let values: GenericScopedVisits's32 = {values: [10, 20, 30]}
    var sum = 0
    var indexes: u64

    for value, ordinal in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(ordinal) == #typeof(@index))
        sum += value
        indexes += ordinal
    }

    @assert(sum == 50)
    @assert(indexes == 3)
}
