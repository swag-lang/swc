#global private

struct JitFieldVisits
{
    x: s32 = 10
    y: s32 = 20
    z: s32 = 30
}

impl JitFieldVisits
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisit(me, stmt: #code(item: s32, index: u64))
    {
        #if ptr do
            #error("JitFieldVisits does not expose pointer iteration.")

        #if back
        {
            for idx in 3
            {
                var visitItem: s32 = undefined
                switch idx
                {
                case 0: visitItem = me.z
                case 1: visitItem = me.y
                case 2: visitItem = me.x
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
            case 2: visitItem = me.z
            }

            #inject(stmt, item = visitItem, index = @index)
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
    func(ptr: bool, back: bool) opVisit(me, stmt: #code(item, index: u64))
    {
        #if back
        {
            #if ptr
            {
                for idx in 3
                {
                    #inject(stmt, item = cast(*s32) &(me.values[2 - idx]), index = @index)
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
                    #inject(stmt, item = cast(*s32) &(me.values[idx]), index = @index)
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

struct JitReverseVisits
{
    values: [3] s32 = [1, 2, 3]
}

impl JitReverseVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: s32, index: u64))
    {
        #if ptr do
            #error("JitReverseVisits does not expose pointer iteration.")

        #if back do
            #error("reverse iteration must use opVisitReverse")

        for idx in 3
        {
            #inject(stmt, item = me.values[idx], index = @index)
        }
    }

    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisitReverse(stmt: #code(item: s32, index: u64))
    {
        #if ptr do
            #error("JitReverseVisits does not expose pointer iteration.")

        for idx in 3
        {
            #inject(stmt, item = me.values[2 - idx], index = @index)
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

struct JitReturnVisits
{
    values: [3] s32 = [4, 5, 6]
}

impl JitHiddenAliasVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: s32, tens: s32, index: u64))
    {
        #if ptr do
            #error("JitHiddenAliasVisits does not expose pointer iteration.")

        #if back do
            #error("JitHiddenAliasVisits does not expose reverse iteration.")

        for idx in 3
        {
            #inject(stmt, item = me.values[idx], tens = me.values[idx] * 10, index = @index)
        }
    }
}

impl JitFieldPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) opVisit(stmt: #code(item, index: u64))
    {
        #if back do
            #error("JitFieldPointerVisits does not expose reverse iteration.")

        #if ptr
        {
            #inject(stmt, item = cast(*s32) &(me.first), index = 0'u64)
            #inject(stmt, item = cast(*s32) &(me.second), index = 1'u64)
            #inject(stmt, item = cast(*s32) &(me.third), index = 2'u64)
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

impl JitPairVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisitPairs(stmt: #code(left: s32, right: s32))
    {
        #if ptr do
            #error("JitPairVisits does not expose pointer iteration.")

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

impl JitConstPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item, index: u64))
    {
        #if back do
            #error("JitConstPointerVisits does not expose reverse iteration.")

        #if ptr
        {
            for idx in 3
            {
                #inject(stmt, item = cast(const *s32) &(me.values[idx]), index = @index)
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

impl JitReturnVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: s32))
    {
        #if ptr do
            #error("JitReturnVisits does not expose pointer iteration.")

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

func jitForeachVisitForward()->s32
{
    var values = JitFieldVisits{}
    var acc: s32

    for value, index in values do
        acc += value + cast(s32) index

    return acc
}

func jitForeachVisitWhere()->s32
{
    var values = JitBufferVisits{}
    var acc: s32

    for value, ordinal in values where value != 6
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

    for &value, ordinal in values do
        dref value += cast(s32) (ordinal + 1)

    return values.values[0] + values.values[1] + values.values[2]
}

func jitForeachVisitReturn()->bool
{
    var values = JitReturnVisits{}

    for value in values
    {
        if value == 6 do
            return true
    }

    return false
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

#test
{
    @assert(jitForeachVisitReturn())
}
