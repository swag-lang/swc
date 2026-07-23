#global private

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
    mtd(ptr: bool, back: bool) opVisit(stmt: #code(item, index: u64))
    {
        #if back do
            #error("Reverse iteration is not used in this forecast example.")

        #if ptr
        {
            #inject(stmt, item = cast(&s32) &(me.monday), index = 0'u64)
            #inject(stmt, item = cast(&s32) &(me.tuesday), index = 1'u64)
            #inject(stmt, item = cast(&s32) &(me.wednesday), index = 2'u64)
            #inject(stmt, item = cast(&s32) &(me.thursday), index = 3'u64)
            #inject(stmt, item = cast(&s32) &(me.friday), index = 4'u64)
        }
        #else
        {
            for idx in 5
            {
                var visitItem: s32 = undefined
                switch idx
                {
                case 0: visitItem = me.monday
                case 1: visitItem = me.tuesday
                case 2: visitItem = me.wednesday
                case 3: visitItem = me.thursday
                case 4: visitItem = me.friday
                }

                #inject(stmt, item = visitItem, index = @index)
            }
        }
    }

    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: s32, index: u64))
    {
        #if back do
            #error("Reverse iteration is not used in this forecast example.")

        #if ptr do
            #error("Address iteration requires a mutable WorkloadForecast receiver.")

        for idx in 5
        {
            var visitItem: s32 = undefined
            switch idx
            {
            case 0: visitItem = me.monday
            case 1: visitItem = me.tuesday
            case 2: visitItem = me.wednesday
            case 3: visitItem = me.thursday
            default: visitItem = me.friday
            }

            #inject(stmt, item = visitItem, index = @index)
        }
    }

    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisitPairs(stmt: #code(today: s32, nextDay: s32))
    {
        #if ptr do
            #error("Pair visits stay read-only in this example.")

        #if back do
            #error("Reverse pair iteration is not used in this forecast example.")

        #inject(stmt, today = me.monday, nextDay = me.tuesday)
        #inject(stmt, today = me.tuesday, nextDay = me.wednesday)
        #inject(stmt, today = me.wednesday, nextDay = me.thursday)
        #inject(stmt, today = me.thursday, nextDay = me.friday)
    }
}

func totalStops(forecast: WorkloadForecast)->s32
{
    var total: s32
    for stops in forecast do
        total += stops
    return total
}

func adjacentSignature(forecast: WorkloadForecast)->s32
{
    var signature: s32
    for #Pairs today, nextDay in forecast do
        signature = signature * 100 + (nextDay - today + 50)
    return signature
}

func maxAdjacentRise(forecast: WorkloadForecast)->s32
{
    var best = -1000
    for #Pairs today, nextDay in forecast
    {
        let delta = nextDay - today
        if delta > best do
            best = delta
    }
    return best
}

// Forecast operations over a struct-backed week with forward, named, and
// by-address custom element-iteration passes.
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

    for &stops, day in forecast
    {
        if day == 2'u64 do
            stops -= 3
        else
        {
            if day == 4'u64 do
                stops -= 5
            else
            {
                if day < 2'u64 do
                    stops += 2
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
