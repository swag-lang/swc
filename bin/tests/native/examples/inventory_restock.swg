#global fileprivate

// Real-life example: prepare a warehouse restock plan from the current inventory.

enum ReorderPriority: u8
{
    Low
    Normal
    Urgent
}

struct InventoryItem
{
    sku:             string
    inStock:         u32
    targetStock:     u32
    unitCostCents:   u32
    leadTimeDays:    u32
    essential:       bool
}

struct RestockPlan
{
    itemCount:              u32
    reorderItemCount:       u32
    totalUnitsToOrder:      u32
    estimatedCostCents:     u32
    delayedEssentialCount:  u32
    priority:               ReorderPriority
    topSku:                 string
}

func missingUnits(item: InventoryItem)->u32
{
    if item.inStock >= item.targetStock do
        return 0

    return item.targetStock - item.inStock
}

func countItemsToReorder(items: const [..] InventoryItem)->u32
{
    var result: u32
    foreach item in items
    {
        if missingUnits(item) != 0 do
            result += 1
    }

    return result
}

func computeUnitsToOrder(items: const [..] InventoryItem)->u32
{
    var result: u32
    foreach item in items do
        result += missingUnits(item)
    return result
}

func computeEstimatedCost(items: const [..] InventoryItem)->u32
{
    var result: u32
    foreach item in items do
        result += missingUnits(item) * item.unitCostCents
    return result
}

func countDelayedEssentialItems(items: const [..] InventoryItem)->u32
{
    var result: u32
    foreach item in items
    {
        if item.essential and missingUnits(item) != 0 and item.leadTimeDays > 7 do
            result += 1
    }

    return result
}

func pickTopSku(items: const [..] InventoryItem)->string
{
    var bestSku = items[0].sku
    var bestMissing = missingUnits(items[0])

    foreach item in items
    {
        let currentMissing = missingUnits(item)
        if currentMissing > bestMissing
        {
            bestMissing = currentMissing
            bestSku = item.sku
        }
    }

    return bestSku
}

func computePriority(items: const [..] InventoryItem)->ReorderPriority
{
    foreach item in items
    {
        if item.essential and missingUnits(item) != 0 and item.leadTimeDays > 7 do
            return ReorderPriority.Urgent
    }

    if computeUnitsToOrder(items) >= 100'u32 do
        return ReorderPriority.Normal

    return ReorderPriority.Low
}

func buildRestockPlan(items: const [..] InventoryItem)->RestockPlan
{
    var result: RestockPlan
    result.itemCount = cast(u32) @countof(items)
    result.reorderItemCount = countItemsToReorder(items)
    result.totalUnitsToOrder = computeUnitsToOrder(items)
    result.estimatedCostCents = computeEstimatedCost(items)
    result.delayedEssentialCount = countDelayedEssentialItems(items)
    result.priority = computePriority(items)
    result.topSku = pickTopSku(items)
    return result
}

#test
{
    const inventory: [4] InventoryItem =
    [
        {sku: "router", inStock: 2, targetStock: 12, unitCostCents: 7500, leadTimeDays: 3, essential: true},
        {sku: "switch-24p", inStock: 1, targetStock: 6, unitCostCents: 18500, leadTimeDays: 10, essential: true},
        {sku: "patch-cable", inStock: 40, targetStock: 120, unitCostCents: 300, leadTimeDays: 2, essential: false},
        {sku: "label-pack", inStock: 25, targetStock: 25, unitCostCents: 900, leadTimeDays: 1, essential: false},
    ]

    @assert(@countof(inventory) == 4)
    @assert(missingUnits(inventory[0]) == 10)
    @assert(missingUnits(inventory[1]) == 5)
    @assert(missingUnits(inventory[2]) == 80)
    @assert(missingUnits(inventory[3]) == 0)
    @assert(countItemsToReorder(inventory) == 3)
    @assert(computeUnitsToOrder(inventory) == 95)
    @assert(computeEstimatedCost(inventory) == 191500'u32)
    @assert(countDelayedEssentialItems(inventory) == 1)
    @assert(pickTopSku(inventory) == "patch-cable")
    @assert(computePriority(inventory) == ReorderPriority.Urgent)

    let plan = buildRestockPlan(inventory)

    @assert(plan.itemCount == 4)
    @assert(plan.reorderItemCount == 3)
    @assert(plan.totalUnitsToOrder == 95)
    @assert(plan.estimatedCostCents == 191500'u32)
    @assert(plan.delayedEssentialCount == 1)
    @assert(plan.priority == ReorderPriority.Urgent)
    @assert(plan.topSku == "patch-cable")
}
