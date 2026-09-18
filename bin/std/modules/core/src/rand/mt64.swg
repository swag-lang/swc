// @LICENCE: BSD-3-Clause
// @ORIGIN: MT19937-64 via CwlUtils, https://github.com/mattgallagher/CwlUtils/blob/master/Sources/ReferenceRandomGenerators/mt19937-64.c
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#mt19937-64

#global namespace Random

const StateSize = 312

const MID      = StateSize / 2
const MM       = 156
const MATRIX_A = 0xB5026F5AA96619E9'u64
const UM       = 0xFFFFFFFF80000000'u64
const LM       = 0x7FFFFFFF'u64

private const DefaultSeed = 5489'u64               // Seed of the reference implementation when none is given
private const Unseeded    = StateSize + 1'u64     // Index of a generator that was never seeded

// The MT19937-64 Mersenne Twister generator.
//
// A generator that was never seeded seeds itself with 5489 on its first draw, like the reference
// implementation. Seed it with [[Core.Random.MersenneTwister64.seedU64]] for another sequence, or
// use it through [[Core.Random.Generator]], which seeds itself from the clock.
#[Swag.Opaque]
public struct MersenneTwister64
{
    internal
    {
        state: [StateSize] u64
        index: u64 = Unseeded
    }
}

public impl MersenneTwister64
{
    // Seeds the generator with a 64-bit value.
    #[Swag.Safety(.Overflow, false)]
    mtd seedU64(seed: u64)
    {
        .state[0] = seed
        .index    = 1
        while .index < StateSize
        {
            .state[.index] = (6364136223846793005'u64 * (.state[.index - 1] ^ (.state[.index - 1] >> 62)) + .index)
            .index         += 1
        }
    }

    // Seeds the generator with a key made of several 64-bit values.
    #[Swag.Safety(.Overflow, false)]
    mtd seedU64(seed: const [..] u64)
    {
        let keyLength = seed.count

        .seedU64(19650218)
        var i = 1
        var j = 0
        var k = StateSize > keyLength ? StateSize : keyLength

        while k
        {
            .state[i] = (.state[i] ^ ((.state[i - 1] ^ (.state[i - 1] >> 62)) * 3935559000370003845)) + seed[j] + j
            i, j      += 1
            if i >= StateSize
            {
                .state[0] = .state[StateSize - 1]
                i         = 1
            }

            if j >= keyLength do
                j = 0
            k -= 1
        }

        k = StateSize - 1
        while k != 0
        {
            .state[i] = (.state[i] ^ ((.state[i - 1] ^ (.state[i - 1] >> 62)) * 2862933555777941757)) - i
            i         += 1
            if i >= StateSize
            {
                .state[0] = .state[StateSize - 1]
                i         = 1
            }

            k -= 1
        }

        .state[0] = 1'u64 << 63
    }

    // Returns the next pseudorandom 64-bit value.
    #[Swag.Safety(.Overflow, false)]
    mtd nextU64()->u64
    {
        if .index == Unseeded do
            .seedU64(DefaultSeed)

        if .index >= StateSize
        {
            let stateMid = .state[MID]

            for var i = 0, j = MID; i != MID - 1; i, j += 1
            {
                let x = (.state[i] & UM) | (.state[i + 1] & LM)
                .state[i] = .state[i + MID] ^ (x >> 1) ^ ((.state[i + 1] & 1) * MATRIX_A)
                let y = (.state[j] & UM) | (.state[j + 1] & LM)
                .state[j] = .state[j - MID] ^ (y >> 1) ^ ((.state[j + 1] & 1) * MATRIX_A)
            }

            let x = (.state[MID - 1] & UM) | (stateMid & LM)
            .state[MID - 1] = .state[StateSize - 1] ^ (x >> 1) ^ ((stateMid & 1) * MATRIX_A)
            let y = (.state[StateSize - 1] & UM) | (.state[0] & LM)
            .state[StateSize - 1] = .state[MID - 1] ^ (y >> 1) ^ ((.state[0] & 1) * MATRIX_A)

            .index = 0
        }

        var result = .state[.index]
        .index += 1

        result ^= (result >> 29) & 0x5555555555555555'u64
        result ^= (result << 17) & 0x71D67FFFEDA60000'u64
        result ^= (result << 37) & 0xFFF7EEE000000000'u64
        result ^= (result >> 43)
        return result
    }
}
