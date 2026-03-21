#global fileprivate

// Real-life example: choose two batteries from each emergency bank to maximize
// the joltage that can be delivered to an escalator control panel.

struct BatteryAudit
{
    bankCount:     u32
    totalOutput:   s32
    highestBank:   s32
    lowestBank:    s32
}

func maxS32(lhs, rhs: s32)->s32
{
    return lhs > rhs ? lhs : rhs
}

func minS32(lhs, rhs: s32)->s32
{
    return lhs < rhs ? lhs : rhs
}

func digitValue(ch: u8)->s32
{
    return cast(s32) (ch - '0')
}

func bestBankOutput(bank: string)->s32
{
    let digits = cast(const [..] u8) bank

    var best = -1

    for i in @countof(digits)
    {
        let first = digitValue(digits[i])

        for j in i + 1 to cast(u64) @countof(digits) - 1
        {
            let second = digitValue(digits[j])
            let value = first * 10 + second
            best = maxS32(best, value)
        }
    }

    return best
}

func auditBanks(banks: const [..] string)->BatteryAudit
{
    var result: BatteryAudit
    result.bankCount = cast(u32) @countof(banks)
    result.lowestBank = Swag.S32.Max

    foreach bank in banks
    {
        let output = bestBankOutput(bank)
        result.totalOutput += output
        result.highestBank = maxS32(result.highestBank, output)
        result.lowestBank = minS32(result.lowestBank, output)
    }

    return result
}

#test
{
    const sampleBanks: [4] string =
    [
        "987654321111111",
        "811111111111119",
        "234234234234278",
        "818181911112111",
    ]

    let sampleAudit = auditBanks(sampleBanks)

    @assert(bestBankOutput(sampleBanks[0]) == 98)
    @assert(bestBankOutput(sampleBanks[1]) == 89)
    @assert(bestBankOutput(sampleBanks[2]) == 78)
    @assert(bestBankOutput(sampleBanks[3]) == 92)
    @assert(sampleAudit.bankCount == 4'u32)
    @assert(sampleAudit.totalOutput == 357)
    @assert(sampleAudit.highestBank == 98)
    @assert(sampleAudit.lowestBank == 78)

    const depotBanks: [5] string =
    [
        "1234512345",
        "7000000009",
        "4545454545",
        "6601234506",
        "1111111188",
    ]

    let depotAudit = auditBanks(depotBanks)

    @assert(bestBankOutput(depotBanks[0]) == 55)
    @assert(bestBankOutput(depotBanks[1]) == 79)
    @assert(bestBankOutput(depotBanks[2]) == 55)
    @assert(bestBankOutput(depotBanks[3]) == 66)
    @assert(bestBankOutput(depotBanks[4]) == 88)
    @assert(depotAudit.bankCount == 5'u32)
    @assert(depotAudit.totalOutput == 343)
    @assert(depotAudit.highestBank == 88)
    @assert(depotAudit.lowestBank == 55)
}
