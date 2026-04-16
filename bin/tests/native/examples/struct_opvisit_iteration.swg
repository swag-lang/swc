#global fileprivate

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
    mtd(ptr: bool, back: bool) opVisit(stmt: #code void)
    {
        #if ptr
        {
            #if back
            {
                #macro
                {
                    var #alias0 = cast(*s32) &(#up me.evening)
                    let #alias1 = 0'u64
                    #inject(#up stmt)
                }

                #macro
                {
                    var #alias0 = cast(*s32) &(#up me.afternoon)
                    let #alias1 = 1'u64
                    #inject(#up stmt)
                }

                #macro
                {
                    var #alias0 = cast(*s32) &(#up me.lunch)
                    let #alias1 = 2'u64
                    #inject(#up stmt)
                }

                #macro
                {
                    var #alias0 = cast(*s32) &(#up me.morning)
                    let #alias1 = 3'u64
                    #inject(#up stmt)
                }

                return
            }

            #macro
            {
                var #alias0 = cast(*s32) &(#up me.morning)
                let #alias1 = 0'u64
                #inject(#up stmt)
            }

            #macro
            {
                var #alias0 = cast(*s32) &(#up me.lunch)
                let #alias1 = 1'u64
                #inject(#up stmt)
            }

            #macro
            {
                var #alias0 = cast(*s32) &(#up me.afternoon)
                let #alias1 = 2'u64
                #inject(#up stmt)
            }

            #macro
            {
                var #alias0 = cast(*s32) &(#up me.evening)
                let #alias1 = 3'u64
                #inject(#up stmt)
            }
        }
        #else
        {
            #if back
            {
                for idx in 4
                {
                    #macro
                    {
                        var #alias0: s32 = undefined

                        switch #up idx
                        {
                        case 0: #alias0 = #up me.evening
                        case 1: #alias0 = #up me.afternoon
                        case 2: #alias0 = #up me.lunch
                        case 3: #alias0 = #up me.morning
                        }

                        let #alias1 = @index
                        #inject(#up stmt)
                    }
                }

                return
            }

            for idx in 4
            {
                #macro
                {
                    var #alias0: s32 = undefined

                    switch #up idx
                    {
                    case 0: #alias0 = #up me.morning
                    case 1: #alias0 = #up me.lunch
                    case 2: #alias0 = #up me.afternoon
                    case 3: #alias0 = #up me.evening
                    }

                    let #alias1 = @index
                    #inject(#up stmt)
                }
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
