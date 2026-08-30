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
    func(ptr: bool) opVisit(me, stmt: #code(item: s32, index: u64))
        where !ptr
    {

        for idx in 3
        {
            var visitItem: s32 = undefined
            switch idx
            {
            case 0:  visitItem = me.x
            case 1:  visitItem = me.y
            default: visitItem = me.z
            }

            #inject(stmt, item = visitItem, index = Swag.index)
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
    func(ptr: bool) opVisit(me, stmt: #code(item, index: u64))
    {
        #static if ptr
        {
            for idx in 3
            {
                #inject(stmt, item = cast(*s32) &(me.values[idx]), index = Swag.index)
            }
        }
        else
        {
            for idx in 3
            {
                #inject(stmt, item = me.values[idx], index = Swag.index)
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
    mtd(ptr: bool) const opVisit(stmt: #code(item: s32, index: u64))
        where !ptr
    {
        for idx in 3
        {
            #inject(stmt, item = me.values[idx], index = Swag.index)
        }
    }

    mtd const reversed() => reverseSlice(me.values)
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
    mtd(ptr: bool) const opVisit(stmt: #code(item: s32, tens: s32, index: u64))
        where !ptr
    {
        for idx in 3
        {
            #inject(stmt, item = me.values[idx], tens = me.values[idx] * 10, index = Swag.index)
        }
    }
}

impl JitFieldPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item, index: u64))
    {
        #static if ptr
        {
            #inject(stmt, item = cast(*s32) &(me.first), index = 0'u64)
            #inject(stmt, item = cast(*s32) &(me.second), index = 1'u64)
            #inject(stmt, item = cast(*s32) &(me.third), index = 2'u64)
        }
        else
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

                #inject(stmt, item = visitItem, index = Swag.index)
            }
        }
    }
}

impl JitPairVisits
{
    mtd const pairs() => pairsView(me.values)
}

impl JitConstPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item, index: u64))
    {
        #static if ptr
        {
            for idx in 3
            {
                #inject(stmt, item = cast(const *s32) &(me.values[idx]), index = Swag.index)
            }
        }
        else
        {
            for idx in 3
            {
                #inject(stmt, item = me.values[idx], index = Swag.index)
            }
        }
    }
}

impl JitReturnVisits
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item: s32))
        where !ptr
    {
        if !(.values).count do
            return

        var remain = (.values).count
        #scope(Up)
        for idx in (.values).count
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

// A visited source reached through a call: the receiver is an lvalue, but re-expanding it
// per use would call again, and a body that only says '.count' names no 'me' at all.
struct JitCallSourceVisits
{
    values: [3] s32 = [7, 8, 9]
    count:  u64     = 3
}

impl JitCallSourceVisits
{
    #[Swag.Macro]
    func(ptr: bool) opVisit(const me, stmt: #code(item, index: u64))
    {
        for idx in .count
        {
            #static if ptr do
                #inject(stmt, item = cast(const *s32) &me.values[idx], index = idx)
            else do
                #inject(stmt, item = me.values[idx], index = idx)
        }
    }
}

var g_JitCallSource:      JitCallSourceVisits
var g_JitCallSourceCalls: s32

func jitCallSource()->const *JitCallSourceVisits
{
    g_JitCallSourceCalls += 1
    return g_JitCallSource
}

func jitForeachVisitCallSource()->s32
{
    g_JitCallSourceCalls = 0
    var sum = 0

    for &value, ordinal in jitCallSource() do
        sum += value[] + cast(s32) ordinal

    // The source expression belongs to the loop, not to the visit body: exactly one evaluation.
    return g_JitCallSourceCalls == 1 ? sum : -1
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
        value[] += cast(s32) (ordinal + 1)

    return values.values[0] + values.values[1] + values.values[2]
}

func jitForeachVisitIndexOnly()->u64
{
    var values = JitBufferVisits{}
    var signature: u64

    for ?, ordinal in values
    {
        #assert(#typeof(ordinal) == u64)
        signature = signature * 10 + ordinal
    }

    return signature
}

func jitForeachVisitSecondOnly()->s32
{
    let values = JitPairVisits{}
    var signature: s32

    for ?, right in values.pairs()
    {
        #assert(#typeof(right) == s32)
        signature = signature * 10 + right
    }

    return signature
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
    const V = #run jitForeachVisitIndexOnly()
    #assert(V == 12)
}

#test
{
    const V = #run jitForeachVisitSecondOnly()
    #assert(V == 468)
}

#test
{
    const V = #run jitForeachVisitCallSource()
    #assert(V == 27)
}

#test
{
    Swag.assert(jitForeachVisitReturn())
}
