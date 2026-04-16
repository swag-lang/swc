#global fileprivate

// Real-life example: a delivery workload forecast exposes several traversal
// modes over weekday fields. Forward iteration sums the week, a named pair
// visit inspects adjacent days, and by-address iteration rebalances capacity.

struct WorkloadForecast
{
    monday:    s32
    tuesday:   s32
    wednesday: s32
    thursday:  s32
    friday:    s32
}

impl WorkloadForecast
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) opVisit(stmt: #code void)
    {
        #if back do
            #error("Reverse iteration is not used in this forecast example.")

        #if ptr
        {
            #macro
            {
                var #alias0: *s32 = cast(*s32) &(#up me.monday)
                let #alias1 = 0'u64
                #inject(#up stmt)
            }

            #macro
            {
                var #alias0: *s32 = cast(*s32) &(#up me.tuesday)
                let #alias1 = 1'u64
                #inject(#up stmt)
            }

            #macro
            {
                var #alias0: *s32 = cast(*s32) &(#up me.wednesday)
                let #alias1 = 2'u64
                #inject(#up stmt)
            }

            #macro
            {
                var #alias0: *s32 = cast(*s32) &(#up me.thursday)
                let #alias1 = 3'u64
                #inject(#up stmt)
            }

            #macro
            {
                var #alias0: *s32 = cast(*s32) &(#up me.friday)
                let #alias1 = 4'u64
                #inject(#up stmt)
            }
        }
        #else
        {
            for idx in 5
            {
                #macro
                {
                    var #alias0: s32 = undefined

                    switch #up idx
                    {
                    case 0: #alias0 = #up me.monday
                    case 1: #alias0 = #up me.tuesday
                    case 2: #alias0 = #up me.wednesday
                    case 3: #alias0 = #up me.thursday
                    case 4: #alias0 = #up me.friday
                    }

                    let #alias1 = @index
                    #inject(#up stmt)
                }
            }
        }
    }

    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisitPairs(stmt: #code void)
    {
        #if ptr do
            #error("Pair visits stay read-only in this example.")

        #if back do
            #error("Reverse pair iteration is not used in this forecast example.")

        #macro
        {
            let #alias0 = #up me.monday
            let #alias1 = #up me.tuesday
            #inject(#up stmt)
        }

        #macro
        {
            let #alias0 = #up me.tuesday
            let #alias1 = #up me.wednesday
            #inject(#up stmt)
        }

        #macro
        {
            let #alias0 = #up me.wednesday
            let #alias1 = #up me.thursday
            #inject(#up stmt)
        }

        #macro
        {
            let #alias0 = #up me.thursday
            let #alias1 = #up me.friday
            #inject(#up stmt)
        }
    }
}

func totalStops(forecast: WorkloadForecast)->s32
{
    var total: s32
    foreach stops in forecast do
        total += stops
    return total
}

func adjacentSignature(forecast: WorkloadForecast)->s32
{
    var signature: s32
    foreach #Pairs today, nextDay in forecast do
        signature = signature * 100 + (nextDay - today + 50)
    return signature
}

func maxAdjacentRise(forecast: WorkloadForecast)->s32
{
    var best = -1000
    foreach #Pairs today, nextDay in forecast
    {
        let delta = nextDay - today
        if delta > best do
            best = delta
    }
    return best
}

// Forecast operations over a struct-backed week with forward, named, and
// by-address custom foreach passes.
#test
{
    var forecast = WorkloadForecast{
        monday: 24,
        tuesday: 28,
        wednesday: 32,
        thursday: 29,
        friday: 35,
    }

    @assert(totalStops(forecast) == 148)
    @assert(adjacentSignature(forecast) == 54544756)
    @assert(maxAdjacentRise(forecast) == 6)

    foreach &stops, day in forecast
    {
        if day == 2'u64 do
            dref stops -= 3
        else
        {
            if day == 4'u64 do
                dref stops -= 5
            else
            {
                if day < 2'u64 do
                    dref stops += 2
            }
        }
    }

    @assert(forecast.monday == 26)
    @assert(forecast.tuesday == 30)
    @assert(forecast.wednesday == 29)
    @assert(forecast.thursday == 29)
    @assert(forecast.friday == 30)
    @assert(totalStops(forecast) == 144)
    @assert(adjacentSignature(forecast) == 54495051)
    @assert(maxAdjacentRise(forecast) == 4)
}
