#global fileprivate

// Real-life example: forecast wholesale price signals by evolving a set of
// obscured vendor seeds and identifying the most profitable repeated pattern.

const SecretMask = 0x00FF_FFFF'u32
const ForecastRounds = 2000
const PriceChangeVariants = 19
const SequenceCount = PriceChangeVariants * PriceChangeVariants * PriceChangeVariants * PriceChangeVariants

var SequenceTotals: [SequenceCount] u32
var SequenceSeenStamp: [SequenceCount] u32

struct MarketForecast
{
    sumAfterForecast: u64
    bestBananaTotal:  u32
}

func nextSecret(secret: u32)->u32
{
    var value = secret
    value = (value ^ (value << 6)) & SecretMask
    value = (value ^ (value >> 5)) & SecretMask
    value = (value ^ (value << 11)) & SecretMask
    return value
}

func priceDigit(secret: u32)->s32
{
    return cast(s32) (secret % 10'u32)
}

func encodeChange(change: s32)->u32
{
    @assert(change >= -9 and change <= 9)
    return cast(u32) (change + 9)
}

func sequenceIndex(change0, change1, change2, change3: s32)->u32
{
    var result = encodeChange(change0)
    result = result * PriceChangeVariants + encodeChange(change1)
    result = result * PriceChangeVariants + encodeChange(change2)
    result = result * PriceChangeVariants + encodeChange(change3)
    return result
}

func analyzeForecast(initialSecrets: const [..] u32)->MarketForecast
{
    var result: MarketForecast

    for SequenceCount
    {
        SequenceTotals[@index] = 0
        SequenceSeenStamp[@index] = 0
    }

    foreach initialSecret, buyerIndex in initialSecrets
    {
        var secret = initialSecret
        var lastPrice = priceDigit(secret)
        var changes: [ForecastRounds] s32
        let buyerStamp = cast(u32) buyerIndex + 1

        for ForecastRounds
        {
            let roundIndex = cast(u32) @index
            secret = nextSecret(secret)
            let currentPrice = priceDigit(secret)
            changes[roundIndex] = currentPrice - lastPrice

            if roundIndex >= 3
            {
                let index = sequenceIndex(
                    changes[roundIndex - 3],
                    changes[roundIndex - 2],
                    changes[roundIndex - 1],
                    changes[roundIndex],
                )

                if SequenceSeenStamp[index] != buyerStamp
                {
                    SequenceSeenStamp[index] = buyerStamp
                    SequenceTotals[index] += cast(u32) currentPrice
                    if SequenceTotals[index] > result.bestBananaTotal do
                        result.bestBananaTotal = SequenceTotals[index]
                }
            }

            lastPrice = currentPrice
        }

        result.sumAfterForecast += cast(u64) secret
    }

    return result
}

#test
{
    var secret = 123'u32
    secret = nextSecret(secret)
    @assert(secret == 15_887_950'u32)

    for 9
    {
        secret = nextSecret(secret)
    }

    @assert(secret == 5_908_254'u32)

    const samplePart1: [4] u32 = [1, 10, 100, 2024]
    const samplePart2: [4] u32 = [1, 2, 3, 2024]

    let forecastPart1 = analyzeForecast(samplePart1)
    let forecastPart2 = analyzeForecast(samplePart2)

    @assert(forecastPart1.sumAfterForecast == 37_327_623'u64)
    @assert(forecastPart2.bestBananaTotal == 23)
}
