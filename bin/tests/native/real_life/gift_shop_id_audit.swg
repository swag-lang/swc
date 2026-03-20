#global fileprivate

// Real-life example: audit gift shop product ID ranges and flag IDs whose
// decimal form is exactly one digit sequence repeated twice.

struct GiftShopAudit
{
    rangeCount:     u32
    invalidCount:   u32
    invalidSum:     u64
    highestInvalid: u64
}

func maxU64(lhs, rhs: u64)->u64
{
    return lhs > rhs ? lhs : rhs
}

func pow10u64(numDigits: u32)->u64
{
    var result = 1'u64
    for numDigits do
        result *= 10'u64
    return result
}

func countDigits(value: u64)->u32
{
    if value < 10'u64 do
        return 1

    var current = value
    var result: u32
    while current != 0'u64
    {
        result += 1
        current /= 10'u64
    }

    return result
}

func isRepeatedDoubleId(value: u64)->bool
{
    let digits = countDigits(value)
    if (digits & 1'u32) != 0'u32 do
        return false

    let splitPower = pow10u64(digits / 2'u32)
    let left = value / splitPower
    let right = value % splitPower
    return left == right
}

func parseNumber(bytes: const [..] u8, index: *u32)->u64
{
    var result: u64
    while dref index < @countof(bytes) and bytes[dref index] >= '0' and bytes[dref index] <= '9'
    {
        result = result * 10'u64 + cast(u64) (bytes[dref index] - '0')
        dref index += 1
    }

    return result
}

func auditProductRanges(sheet: string)->GiftShopAudit
{
    let bytes = cast(const [..] u8) sheet

    var result: GiftShopAudit
    var index: u32

    while index < @countof(bytes)
    {
        let firstId = parseNumber(bytes, &index)
        @assert(index < @countof(bytes) and bytes[index] == '-')
        index += 1

        let lastId = parseNumber(bytes, &index)
        result.rangeCount += 1

        var productId = firstId
        while productId <= lastId
        {
            if isRepeatedDoubleId(productId)
            {
                result.invalidCount += 1
                result.invalidSum += productId
                result.highestInvalid = maxU64(result.highestInvalid, productId)
            }

            productId += 1
        }

        if index < @countof(bytes) and bytes[index] == ',' do
            index += 1
    }

    return result
}

#test
{
    const exampleSheet = "11-22,95-115,998-1012,1188511880-1188511890,222220-222224,1698522-1698528,446443-446449,38593856-38593862,565653-565659,824824821-824824827,2121212118-2121212124"
    let exampleAudit = auditProductRanges(exampleSheet)

    @assert(exampleAudit.rangeCount == 11'u32)
    @assert(exampleAudit.invalidCount == 8'u32)
    @assert(exampleAudit.invalidSum == 1227775554'u64)
    @assert(exampleAudit.highestInvalid == 1188511885'u64)

    const boutiqueSheet = "10-12,1200-1235,9898-9902,777776-777778"
    let boutiqueAudit = auditProductRanges(boutiqueSheet)

    @assert(boutiqueAudit.rangeCount == 4'u32)
    @assert(boutiqueAudit.invalidCount == 4'u32)
    @assert(boutiqueAudit.invalidSum == 788898'u64)
    @assert(boutiqueAudit.highestInvalid == 777777'u64)
}
