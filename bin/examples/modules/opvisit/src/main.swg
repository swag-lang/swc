using Core

// Demonstrate custom foreach over a struct through opVisit, including
// by-address updates and a dedicated named variant through opVisitReverse.

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
            #if back do
                #error("Use foreach #Reverse to iterate ShelfBins in reverse order.")

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

    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisitReverse(stmt: #code void)
    {
        #if ptr do
            #error("This example keeps reverse iteration read-only.")

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
    }
}

func countUnits(bins: ShelfBins)->s32
{
    var total: s32
    foreach units in bins do
        total += units
    return total
}

func reverseCode(bins: ShelfBins)->s32
{
    var code: s32
    foreach #Reverse units in bins do
        code = code * 10 + units
    return code
}

#main
{
    var bins = ShelfBins{morning: 2, lunch: 4, afternoon: 6, evening: 8}

    Console.print("initial total: ", countUnits(bins), "\n")
    Console.print("initial reverse code: ", reverseCode(bins), "\n")

    @assert(countUnits(bins) == 20)
    @assert(reverseCode(bins) == 8642)

    foreach &units, slot in bins
    {
        if slot != 1'u64 do
            dref units += 3 + cast(s32) slot
    }

    Console.print("restocked total: ", countUnits(bins), "\n")
    Console.print("restocked reverse code: ", reverseCode(bins), "\n")

    @assert(bins.morning == 5)
    @assert(bins.lunch == 4)
    @assert(bins.afternoon == 11)
    @assert(bins.evening == 14)
    @assert(countUnits(bins) == 34)
    @assert(reverseCode(bins) == 15145)
}
