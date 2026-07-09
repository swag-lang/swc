#global private

// Real-life example: track inventory across four front-of-house bins and expose
// a custom foreach over the struct itself through opVisit.

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
                #inject(stmt, item = cast(*s32) &(me.evening), index = 0'u64)
                #inject(stmt, item = cast(*s32) &(me.afternoon), index = 1'u64)
                #inject(stmt, item = cast(*s32) &(me.lunch), index = 2'u64)
                #inject(stmt, item = cast(*s32) &(me.morning), index = 3'u64)
                return
            }

            #inject(stmt, item = cast(*s32) &(me.morning), index = 0'u64)
            #inject(stmt, item = cast(*s32) &(me.lunch), index = 1'u64)
            #inject(stmt, item = cast(*s32) &(me.afternoon), index = 2'u64)
            #inject(stmt, item = cast(*s32) &(me.evening), index = 3'u64)
        }
        #else
        {
            #if back
            {
                for idx in 4
                {
                    switch idx
                    {
                    case 0: #inject(stmt, item = me.evening, index = @index)
                    case 1: #inject(stmt, item = me.afternoon, index = @index)
                    case 2: #inject(stmt, item = me.lunch, index = @index)
                    case 3: #inject(stmt, item = me.morning, index = @index)
                    }
                }

                return
            }

            for idx in 4
            {
                switch idx
                {
                case 0: #inject(stmt, item = me.morning, index = @index)
                case 1: #inject(stmt, item = me.lunch, index = @index)
                case 2: #inject(stmt, item = me.afternoon, index = @index)
                case 3: #inject(stmt, item = me.evening, index = @index)
                }
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
                switch idx
                {
                case 0: #inject(stmt, item = me.evening, index = @index)
                case 1: #inject(stmt, item = me.afternoon, index = @index)
                case 2: #inject(stmt, item = me.lunch, index = @index)
                case 3: #inject(stmt, item = me.morning, index = @index)
                }
            }

            return
        }

        for idx in 4
        {
            switch idx
            {
            case 0: #inject(stmt, item = me.morning, index = @index)
            case 1: #inject(stmt, item = me.lunch, index = @index)
            case 2: #inject(stmt, item = me.afternoon, index = @index)
            case 3: #inject(stmt, item = me.evening, index = @index)
            }
        }
    }
}

func countUnits(bins: ShelfBins)->s32
{
    var total: s32
    foreach readUnits in bins do
        total += readUnits
    return total
}

func reverseCode(bins: ShelfBins)->s32
{
    var code: s32
    foreach #reverse reverseUnits in bins do
        code = code * 10 + reverseUnits
    return code
}

// Custom foreach over struct fields with forward, reverse, and by-address passes
#test
{
    var bins = ShelfBins{morning: 2, lunch: 4, afternoon: 6, evening: 8}

    @assert(countUnits(bins) == 20)
    @assert(reverseCode(bins) == 8642)

    foreach &writeUnits, slot in bins
    {
        if slot != 1'u64 do
            dref writeUnits += 3 + cast(s32) slot
    }

    @assert(bins.morning == 5)
    @assert(bins.lunch == 4)
    @assert(bins.afternoon == 11)
    @assert(bins.evening == 14)
    @assert(countUnits(bins) == 34)
    @assert(reverseCode(bins) == 15145)
}
