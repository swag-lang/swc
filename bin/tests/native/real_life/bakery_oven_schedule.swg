#global fileprivate

// Real-life example: plan a bakery oven shift with tray capacity, temperature
// setups, steam batches, and cooling time before the storefront opens.

struct BakeOrder
{
    sku:             string
    currentTrays:    s32
    targetTrays:     s32
    ovenTempC:       s32
    minutesPerBatch: s32
    coolingMinutes:  s32
    needsSteam:      bool
}

struct OvenSchedule
{
    batchCount:        s32
    steamBatchCount:   s32
    traysProduced:     s32
    setupCount:        s32
    setupMinutes:      s32
    bakeMinutes:       s32
    ovenBusyMinutes:   s32
    lastBakeMinute:    s32
    finalReadyMinute:  s32
    opensOnTime:       bool
}

func maxS32(lhs, rhs: s32)->s32
{
    return lhs > rhs ? lhs : rhs
}

func minS32(lhs, rhs: s32)->s32
{
    return lhs < rhs ? lhs : rhs
}

func clampNeededTrays(order: BakeOrder)->s32
{
    let needed = order.targetTrays - order.currentTrays
    return needed > 0 ? needed : 0
}

func ceilDiv(value, divisor: s32)->s32
{
    return (value + divisor - 1) / divisor
}

func buildSchedule(orders: const [..] BakeOrder, trayCapacity: s32, shiftStartMinute: s32, openingMinute: s32)->OvenSchedule
{
    var result: OvenSchedule
    var currentMinute = shiftStartMinute
    var currentTemp = -1

    foreach order in orders
    {
        let traysNeeded = clampNeededTrays(order)
        if traysNeeded == 0 do
            continue

        if currentTemp != order.ovenTempC
        {
            currentTemp = order.ovenTempC
            result.setupCount += 1
            result.setupMinutes += 12
            currentMinute += 12
        }

        let totalBatches = ceilDiv(traysNeeded, trayCapacity)
        var traysRemaining = traysNeeded

        for cast(u32) totalBatches
        {
            let traysThisBatch = minS32(traysRemaining, trayCapacity)
            traysRemaining -= traysThisBatch

            result.batchCount += 1
            result.traysProduced += traysThisBatch
            result.bakeMinutes += order.minutesPerBatch
            if order.needsSteam do
                result.steamBatchCount += 1

            currentMinute += order.minutesPerBatch
        }

        result.finalReadyMinute = maxS32(result.finalReadyMinute, currentMinute + order.coolingMinutes)
    }

    result.lastBakeMinute = currentMinute
    result.ovenBusyMinutes = currentMinute - shiftStartMinute
    result.opensOnTime = result.finalReadyMinute <= openingMinute
    return result
}

#test
{
    const weekdayPrep: [4] BakeOrder =
    [
        {sku: "croissant", currentTrays: 4, targetTrays: 10, ovenTempC: 195, minutesPerBatch: 18, coolingMinutes: 25, needsSteam: true},
        {sku: "baguette", currentTrays: 0, targetTrays: 4, ovenTempC: 235, minutesPerBatch: 16, coolingMinutes: 15, needsSteam: true},
        {sku: "cinnamon-roll", currentTrays: 3, targetTrays: 7, ovenTempC: 180, minutesPerBatch: 20, coolingMinutes: 30, needsSteam: false},
        {sku: "muffin", currentTrays: 8, targetTrays: 8, ovenTempC: 175, minutesPerBatch: 19, coolingMinutes: 12, needsSteam: false},
    ]

    let weekdaySchedule = buildSchedule(weekdayPrep, 2, 240, 420)

    @assert(weekdaySchedule.batchCount == 7)
    @assert(weekdaySchedule.steamBatchCount == 5)
    @assert(weekdaySchedule.traysProduced == 14)
    @assert(weekdaySchedule.setupCount == 3)
    @assert(weekdaySchedule.setupMinutes == 36)
    @assert(weekdaySchedule.bakeMinutes == 126)
    @assert(weekdaySchedule.ovenBusyMinutes == 162)
    @assert(weekdaySchedule.lastBakeMinute == 402)
    @assert(weekdaySchedule.finalReadyMinute == 432)
    @assert(weekdaySchedule.opensOnTime == false)

    const marketPrep: [3] BakeOrder =
    [
        {sku: "berry-scone", currentTrays: 1, targetTrays: 7, ovenTempC: 190, minutesPerBatch: 15, coolingMinutes: 10, needsSteam: false},
        {sku: "focaccia", currentTrays: 0, targetTrays: 3, ovenTempC: 220, minutesPerBatch: 22, coolingMinutes: 20, needsSteam: false},
        {sku: "brioche", currentTrays: 2, targetTrays: 7, ovenTempC: 180, minutesPerBatch: 24, coolingMinutes: 35, needsSteam: true},
    ]

    let marketSchedule = buildSchedule(marketPrep, 3, 180, 390)

    @assert(marketSchedule.batchCount == 5)
    @assert(marketSchedule.steamBatchCount == 2)
    @assert(marketSchedule.traysProduced == 14)
    @assert(marketSchedule.setupCount == 3)
    @assert(marketSchedule.setupMinutes == 36)
    @assert(marketSchedule.bakeMinutes == 100)
    @assert(marketSchedule.ovenBusyMinutes == 136)
    @assert(marketSchedule.lastBakeMinute == 316)
    @assert(marketSchedule.finalReadyMinute == 351)
    @assert(marketSchedule.opensOnTime)
}
