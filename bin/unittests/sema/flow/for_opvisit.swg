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
    func(ptr: bool) opVisit(me, stmt: #code(item: s32, index))
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

struct SemaBufferVisits
{
    values: [3] s32 = [3, 6, 9]
}

impl SemaBufferVisits
{
    #[Swag.Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item, index))
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
    mtd(ptr: bool) const opVisit(stmt: #code(item: s32, tens: s32, index))
        where !ptr
    {
        for idx in 3
        {
            #inject(stmt, item = me.values[idx], tens = me.values[idx] * 10, index = Swag.index)
        }
    }
}

impl SemaFieldPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item, index))
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

impl SemaReverseVisits
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item: s32, index))
        where !ptr
    {
        for idx in 3
        {
            #inject(stmt, item = me.values[idx], index = Swag.index)
        }
    }

    mtd const reversed() => reverseSlice(me.values)
}

impl SemaGenericReverseVisits
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item, index))
        where !ptr
    {

        for idx in 3
        {
            #inject(stmt, item = me.values[idx], index = Swag.index)
        }
    }

    mtd const reversed() => reverseSlice(me.values)
}

impl SemaPairVisits
{
    mtd const pairs() => pairsView(me.values)
}

impl SemaConstPointerVisits
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item, index))
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

struct(T) SemaGenericScopedVisits
{
    const FIRST = 1'u64
    values: [3] T
}

impl SemaGenericScopedVisits
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item, index))
        where !ptr
    {
        #scope(Outer)
        for 3
        {
            if Swag.index < SemaGenericScopedVisits.FIRST do
                continue

            #scope(Inner)
            {
                #inject(stmt, item = me.values[Swag.index], index = Swag.index, break = break to Outer, continue = break to Inner)
            }
        }
    }
}

func semaTest001()
{
    var values = SemaBufferVisits{}
    for &value, ordinal in values
    {
        #assert(#typeof(value) == #type *s32)
        #assert(#typeof(ordinal) == #typeof(Swag.index))
        var x = value
    }
}

func semaTest002()
{
    var values = SemaReverseVisits{}

    for value, ordinal in (values).reversed()
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(ordinal) == #typeof(Swag.index))
        var x = value
        var y = ordinal
    }
}

func semaTest002b()
{
    var values: SemaGenericReverseVisits's32
    values.values = [1, 2, 3]

    for value, ordinal in (values).reversed()
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(ordinal) == #typeof(Swag.index))
        var x = value
        var y = ordinal
    }
}

func semaTest003()
{
    var values = SemaHiddenAliasVisits{}

    for value in values
    {
        let ordinal = Swag.index
        var x       = ordinal
        var y       = value
    }
}

func semaTest004()
{
    var values = SemaHiddenAliasVisits{}

    for value in values
    {
        #assert(#typeof(value) == s32)
        let ordinal = Swag.index
        var x       = value
        var y       = ordinal
    }
}

func semaTest005()
{
    var values = SemaHiddenAliasVisits{}

    for value, scaled in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(scaled) == s32)
        let ordinal = Swag.index
        var x       = value
        var y       = scaled
        var z       = ordinal
    }
}

func semaTest005b()
{
    let values = SemaHiddenAliasVisits{}

    for value, scaled, index in values
    {
        var x = value
        var y = scaled
        var z = index
    }
}

func semaTest006()
{
    var values = SemaFieldPointerVisits{}

    for &value, ordinal in values
    {
        #assert(#typeof(value) == #type *s32)
        var x = value
        var y = ordinal
    }
}

func semaTest007()
{
    var values = SemaPairVisits{}

    for left, right in values.pairs()
    {
        #assert(#typeof(left) == s32)
        #assert(#typeof(right) == s32)
        let ordinal = Swag.index
        var x       = left
        var y       = right
        var z       = ordinal
    }
}

func semaTest008()
{
    let values = SemaConstPointerVisits{}

    for &value, ordinal in values
    {
        #assert(#typeof(value) == #type const *s32)
        var x = value
        var y = ordinal
    }
}

func semaTest009()
{
    let values: SemaGenericScopedVisits's32 = {values: [10, 20, 30]}

    for value, ordinal in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(ordinal) == #typeof(Swag.index))
        var x = value
        var y = ordinal
    }
}

func semaTest010()
{
    var visits       = SemaReverseVisits{}
    var outside: s32 = 0
    var inside:  s32 = 0

    for value, i in visits
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
