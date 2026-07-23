#global private

// Real-life example: track inventory across four front-of-house bins and expose
// a custom element iteration over the struct itself through opVisit.

struct ShelfBins
{
    morning:   s32
    lunch:     s32
    afternoon: s32
    evening:   s32
}

impl ShelfBins
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) opVisit(stmt: #code(item, index: u64))
    {
        #if ptr
        {
            #if back
            {
                #inject(stmt, item = cast(&s32) &(me.evening), index = 0'u64)
                #inject(stmt, item = cast(&s32) &(me.afternoon), index = 1'u64)
                #inject(stmt, item = cast(&s32) &(me.lunch), index = 2'u64)
                #inject(stmt, item = cast(&s32) &(me.morning), index = 3'u64)
                return
            }

            #inject(stmt, item = cast(&s32) &(me.morning), index = 0'u64)
            #inject(stmt, item = cast(&s32) &(me.lunch), index = 1'u64)
            #inject(stmt, item = cast(&s32) &(me.afternoon), index = 2'u64)
            #inject(stmt, item = cast(&s32) &(me.evening), index = 3'u64)
        }
        #else
        {
            #if back
            {
                for idx in 4
                {
                    var visitItem: s32 = undefined
                    switch idx
                    {
                    case 0: visitItem = me.evening
                    case 1: visitItem = me.afternoon
                    case 2: visitItem = me.lunch
                    case 3: visitItem = me.morning
                    }

                    #inject(stmt, item = visitItem, index = @index)
                }

                return
            }

            for idx in 4
            {
                var visitItem: s32 = undefined
                switch idx
                {
                case 0: visitItem = me.morning
                case 1: visitItem = me.lunch
                case 2: visitItem = me.afternoon
                case 3: visitItem = me.evening
                }

                #inject(stmt, item = visitItem, index = @index)
            }
        }
    }

    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: s32, index: u64))
    {
        #if ptr do
            #error("Address iteration requires a mutable ShelfBins receiver.")

        #if back
        {
            for idx in 4
            {
                var visitItem: s32 = undefined
                switch idx
                {
                case 0:  visitItem = me.evening
                case 1:  visitItem = me.afternoon
                case 2:  visitItem = me.lunch
                default: visitItem = me.morning
                }

                #inject(stmt, item = visitItem, index = @index)
            }

            return
        }

        for idx in 4
        {
            var visitItem: s32 = undefined
            switch idx
            {
            case 0:  visitItem = me.morning
            case 1:  visitItem = me.lunch
            case 2:  visitItem = me.afternoon
            default: visitItem = me.evening
            }

            #inject(stmt, item = visitItem, index = @index)
        }
    }
}

func countUnits(bins: ShelfBins)->s32
{
    var total: s32
    for readUnits in bins do
        total += readUnits
    return total
}

func reverseCode(bins: ShelfBins)->s32
{
    var code: s32
    for #reverse reverseUnits in bins do
        code = code * 10 + reverseUnits
    return code
}

// Custom element iteration over struct fields with forward, reverse, and by-address passes
#test
{
    var bins = ShelfBins{morning: 2, lunch: 4, afternoon: 6, evening: 8}

    @assert(countUnits(bins) == 20)
    @assert(reverseCode(bins) == 8642)

    for &writeUnits, slot in bins
    {
        if slot != 1'u64 do
            writeUnits += 3 + cast(s32) slot
    }

    @assert(bins.morning == 5)
    @assert(bins.lunch == 4)
    @assert(bins.afternoon == 11)
    @assert(bins.evening == 14)
    @assert(countUnits(bins) == 34)
    @assert(reverseCode(bins) == 15145)
}
