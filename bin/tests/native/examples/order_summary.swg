#global fileprivate

// Real-life example: compute the summary of a small online order.

enum CustomerTier: u8
{
    Standard
    Silver
    Gold
}

struct OrderLine
{
    sku:             string
    unitPriceCents:  u32
    quantity:        u32
    fragile:         bool
}

struct OrderSummary
{
    unitCount:         u32
    subtotalCents:     u32
    packagingCents:    u32
    discountCents:     u32
    totalCents:        u32
    needsSignature:    bool
}

func countUnits(lines: const [..] OrderLine)->u32
{
    var result: u32
    foreach line in lines do
        result += line.quantity
    return result
}

func computeSubtotal(lines: const [..] OrderLine)->u32
{
    var result: u32
    foreach line in lines do
        result += line.unitPriceCents * line.quantity
    return result
}

func hasFragileLine(lines: const [..] OrderLine)->bool
{
    foreach line in lines
    {
        if line.fragile do
            return true
    }

    return false
}

func computePackaging(lines: const [..] OrderLine)->u32
{
    const BasePackaging = 250'u32
    const UnitPackaging = 50'u32
    const FragileExtra  = 200'u32

    var result = BasePackaging
    foreach line in lines
    {
        result += UnitPackaging * line.quantity
        if line.fragile do
            result += FragileExtra
    }

    return result
}

func computeDiscount(subtotalCents: u32, tier: CustomerTier)->u32
{
    if tier == CustomerTier.Gold and subtotalCents >= 15000'u32 do
        return subtotalCents / 10

    if tier == CustomerTier.Silver and subtotalCents >= 10000'u32 do
        return subtotalCents / 20

    return 0
}

func findTopSku(lines: const [..] OrderLine)->string
{
    var bestSku = lines[0].sku
    var bestPrice = lines[0].unitPriceCents

    foreach line in lines
    {
        if line.unitPriceCents > bestPrice
        {
            bestPrice = line.unitPriceCents
            bestSku = line.sku
        }
    }

    return bestSku
}

func buildOrderSummary(lines: const [..] OrderLine, tier: CustomerTier)->OrderSummary
{
    var result: OrderSummary
    result.unitCount = countUnits(lines)
    result.subtotalCents = computeSubtotal(lines)
    result.packagingCents = computePackaging(lines)
    result.discountCents = computeDiscount(result.subtotalCents, tier)
    result.totalCents = result.subtotalCents + result.packagingCents - result.discountCents
    result.needsSignature = hasFragileLine(lines) or result.totalCents >= 20000'u32
    return result
}

#test
{
    const order: [3] OrderLine =
    [
        {sku: "mechanical-keyboard", unitPriceCents: 12900, quantity: 1, fragile: true},
        {sku: "usb-c-cable", unitPriceCents: 1500, quantity: 2, fragile: false},
        {sku: "wrist-rest", unitPriceCents: 3500, quantity: 1, fragile: false},
    ]

    @assert(@countof(order) == 3)
    @assert(order[0].quantity == 1)
    @assert(order[1].quantity == 2)
    @assert(order[2].quantity == 1)
    @assert(countUnits(order) == 4)
    @assert(computeSubtotal(order) == 19400'u32)
    @assert(computePackaging(order) == 650'u32)
    @assert(hasFragileLine(order))
    @assert(findTopSku(order) == "mechanical-keyboard")

    let standard = buildOrderSummary(order, CustomerTier.Standard)
    let silver   = buildOrderSummary(order, CustomerTier.Silver)
    let gold     = buildOrderSummary(order, CustomerTier.Gold)

    @assert(standard.unitCount == 4)
    @assert(standard.subtotalCents == 19400'u32)
    @assert(standard.packagingCents == 650'u32)
    @assert(standard.discountCents == 0'u32)
    @assert(standard.totalCents == 20050'u32)
    @assert(standard.needsSignature)

    @assert(silver.discountCents == 970'u32)
    @assert(silver.totalCents == 19080'u32)
    @assert(silver.needsSignature)

    @assert(gold.discountCents == 1940'u32)
    @assert(gold.totalCents == 18110'u32)
    @assert(gold.needsSignature)
}
