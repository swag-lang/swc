#global private

// Real-life example: choose two batteries from each emergency bank to maximize
// the joltage that can be delivered to an escalator control panel.

struct BatteryAudit
{
    bankCount:   u32
    totalOutput: s32
    highestBank: s32
    lowestBank:  s32
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

    for i in digits.count
    {
        let first = digitValue(digits[i])
        if i + 1 >= digits.count do continue

        for j in i + 1 to cast(u64) digits.count - 1
        {
            let second = digitValue(digits[j])
            let value  = first * 10 + second
            best = maxS32(best, value)
        }
    }

    return best
}

func auditBanks(banks: const [..] string)->BatteryAudit
{
    var result: BatteryAudit
    result.bankCount  = cast(u32) banks.count
    result.lowestBank = Swag.S32.Max

    for bank in banks
    {
        let output = bestBankOutput(bank)
        result.totalOutput += output
        result.highestBank = maxS32(result.highestBank, output)
        result.lowestBank  = minS32(result.lowestBank, output)
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
        "818181911112111"
        ]

    let sampleAudit = auditBanks(sampleBanks)

    Swag.assert(bestBankOutput(sampleBanks[0]) == 98)
    Swag.assert(bestBankOutput(sampleBanks[1]) == 89)
    Swag.assert(bestBankOutput(sampleBanks[2]) == 78)
    Swag.assert(bestBankOutput(sampleBanks[3]) == 92)
    Swag.assert(sampleAudit.bankCount == 4'u32)
    Swag.assert(sampleAudit.totalOutput == 357)
    Swag.assert(sampleAudit.highestBank == 98)
    Swag.assert(sampleAudit.lowestBank == 78)

    const depotBanks: [5] string =
        [
        "1234512345",
        "7000000009",
        "4545454545",
        "6601234506",
        "1111111188"
        ]

    let depotAudit = auditBanks(depotBanks)

    Swag.assert(bestBankOutput(depotBanks[0]) == 55)
    Swag.assert(bestBankOutput(depotBanks[1]) == 79)
    Swag.assert(bestBankOutput(depotBanks[2]) == 55)
    Swag.assert(bestBankOutput(depotBanks[3]) == 66)
    Swag.assert(bestBankOutput(depotBanks[4]) == 88)
    Swag.assert(depotAudit.bankCount == 5'u32)
    Swag.assert(depotAudit.totalOutput == 343)
    Swag.assert(depotAudit.highestBank == 88)
    Swag.assert(depotAudit.lowestBank == 55)
}
