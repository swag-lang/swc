#global private

alias VisitAlias = SemaFieldVisits

struct SemaFieldVisits
{
    x: s32 = 10
    y: s32 = 20
    z: s32 = 30
}

impl SemaFieldVisits
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisit(me, stmt: #code(item: s32, index))
    {
        #if ptr do
            #error("SemaFieldVisits does not expose pointer iteration.")

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

struct SemaBufferVisits
{
    values: [3] s32 = [3, 6, 9]
}

impl SemaBufferVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) opVisit(stmt: #code(item, index))
    {
        #if back do
            #error("SemaBufferVisits does not expose reverse iteration.")

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

struct SemaHiddenAliasVisits
{
    values: [3] s32 = [4, 5, 6]
}

struct SemaFieldPointerVisits
{
    first:  s32 = 1
    second: s32 = 2
    third:  s32 = 3
}

struct SemaReverseVisits
{
    values: [3] s32 = [1, 2, 3]
}

struct(T) SemaGenericReverseVisits
{
    values: [3] T
}

struct SemaPairVisits
{
    values: [4] s32 = [2, 4, 6, 8]
}

struct SemaConstPointerVisits
{
    values: [3] s32 = [7, 8, 9]
}

impl SemaHiddenAliasVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: s32, tens: s32, index))
    {
        #if ptr do
            #error("SemaHiddenAliasVisits does not expose pointer iteration.")

        #if back do
            #error("SemaHiddenAliasVisits does not expose reverse iteration.")

        for idx in 3
        {
            #inject(stmt, item = me.values[idx], tens = me.values[idx] * 10, index = @index)
        }
    }
}

impl SemaFieldPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) opVisit(stmt: #code(item, index))
    {
        #if back do
            #error("SemaFieldPointerVisits does not expose reverse iteration.")

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

impl SemaReverseVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: s32, index))
    {
        #if ptr do
            #error("SemaReverseVisits does not expose pointer iteration.")

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
            #error("SemaReverseVisits does not expose pointer iteration.")

        for idx in 3
        {
            #inject(stmt, item = me.values[2 - idx], index = @index)
        }
    }
}

impl SemaGenericReverseVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item, index))
    {
        #if ptr do
            #error("SemaGenericReverseVisits does not expose pointer iteration.")

        #if back
        {
            for idx in 3
            {
                #inject(stmt, item = me.values[2 - idx], index = @index)
            }

            return
        }

        for idx in 3
        {
            #inject(stmt, item = me.values[idx], index = @index)
        }
    }
}

impl SemaPairVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisitPairs(stmt: #code(left: s32, right: s32))
    {
        #if ptr do
            #error("SemaPairVisits does not expose pointer iteration.")

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

impl SemaConstPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item, index))
    {
        #if back do
            #error("SemaConstPointerVisits does not expose reverse iteration.")

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

struct(T) SemaGenericScopedVisits
{
    const FIRST = 1'u64
    values: [3] T
}

impl SemaGenericScopedVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item, index))
    {
        #if ptr do
            #error("SemaGenericScopedVisits does not expose pointer iteration.")

        #if back do
            #error("SemaGenericScopedVisits does not expose reverse iteration.")

        #scope(Outer)
        for 3
        {
            if @index < SemaGenericScopedVisits.FIRST do
                continue

            #scope(Inner)
            {
                #inject(stmt, item = me.values[@index], index = @index, break = break to Outer, continue = break to Inner)
            }
        }
    }
}

func semaTest001()
{
    var values = SemaBufferVisits{}
    foreach &value, ordinal in values
    {
        #assert(#typeof(dref value) == s32)
        #assert(#typeof(ordinal) == #typeof(@index))
        var x = dref value
    }
}

func semaTest002()
{
    var values = SemaReverseVisits{}

    foreach #Reverse value, ordinal in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(ordinal) == #typeof(@index))
        var x = value
        var y = ordinal
    }
}

func semaTest002b()
{
    var values: SemaGenericReverseVisits's32
    values.values = [1, 2, 3]

    foreach #reverse value, ordinal in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(ordinal) == #typeof(@index))
        var x = value
        var y = ordinal
    }
}

func semaTest003()
{
    var values = SemaHiddenAliasVisits{}

    foreach values
    {
        let ordinal = @index
        var x = ordinal
    }
}

func semaTest004()
{
    var values = SemaHiddenAliasVisits{}

    foreach value in values
    {
        #assert(#typeof(value) == s32)
        let ordinal = @index
        var x = value
        var y = ordinal
    }
}

func semaTest005()
{
    var values = SemaHiddenAliasVisits{}

    foreach value, scaled in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(scaled) == s32)
        let ordinal = @index
        var x = value
        var y = scaled
        var z = ordinal
    }
}

func semaTest006()
{
    var values = SemaFieldPointerVisits{}

    foreach &value, ordinal in values
    {
        #assert(#typeof(value) == *s32)
        var x = dref value
        var y = ordinal
    }
}

func semaTest007()
{
    var values = SemaPairVisits{}

    foreach #Pairs left, right in values
    {
        #assert(#typeof(left) == s32)
        #assert(#typeof(right) == s32)
        let ordinal = @index
        var x = left
        var y = right
        var z = ordinal
    }
}

func semaTest008()
{
    let values = SemaConstPointerVisits{}

    foreach &value, ordinal in values
    {
        #assert(#typeof(value) == const *s32)
        var x = dref value
        var y = ordinal
    }
}

func semaTest009()
{
    let values: SemaGenericScopedVisits's32 = {values: [10, 20, 30]}

    foreach value, ordinal in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(ordinal) == #typeof(@index))
        var x = value
        var y = ordinal
    }
}

func semaTest010()
{
    var visits = SemaReverseVisits{}
    var outside: s32 = 0
    var inside: s32 = 0

    foreach value, i in visits
    {
        if !(i & 1) do
            outside += value
        else do
            inside += value
    }

    for i in 0 until 1
    {
        var x = i
    }

    var total = outside + inside
}
