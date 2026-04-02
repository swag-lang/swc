#global fileprivate

// Real-life example: combine seeded randomness and procedural noise to build a
// reproducible community-garden layout.

struct GardenPlanSummary
{
    pondPlots:          s32
    wildflowerPlots:    s32
    stonePathPlots:     s32
    vegetablePlots:     s32
    irrigatedPlots:     s32
    raisedBeds:         s32
    compostBins:        s32
    waterReserveLiters: s32
    fertilityScore:     s32
    layoutSignature:    s32
}

struct GardenRng
{
    state: u64
}

impl GardenRng
{
    mtd seed(seed: u64)
    {
        .state = seed | 1'u64
    }

    #[Swag.CanOverflow(true)]
    mtd nextU32()->u32
    {
        .state = .state * 6364136223846793005'u64 + 1442695040888963407'u64
        return cast(u32) (.state >> 32)
    }

    mtd nextF32()->f32
    {
        var value = .nextU32()
        while value == Swag.U32.Max do
            value = .nextU32()
        return cast(f32) value / cast(f32) Swag.U32.Max
    }

    mtd nextF32(min, max: f32)->f32
    {
        let alpha = .nextF32()
        return min + (max - min) * alpha
    }

    mtd nextS32(min, max: s32)->s32
    {
        let range = cast(u32) (max - min)
        let value = cast(s32) (.nextU32() % range)
        return min + value
    }

    mtd nextBool()->bool
    {
        return (.nextU32() & 1'u32) != 0'u32
    }
}

func sameSummary(lhs, rhs: GardenPlanSummary)->bool
{
    return lhs.pondPlots == rhs.pondPlots and
           lhs.wildflowerPlots == rhs.wildflowerPlots and
           lhs.stonePathPlots == rhs.stonePathPlots and
           lhs.vegetablePlots == rhs.vegetablePlots and
           lhs.irrigatedPlots == rhs.irrigatedPlots and
           lhs.raisedBeds == rhs.raisedBeds and
           lhs.compostBins == rhs.compostBins and
           lhs.waterReserveLiters == rhs.waterReserveLiters and
           lhs.fertilityScore == rhs.fertilityScore and
           lhs.layoutSignature == rhs.layoutSignature
}

func smoothStep(value: f32)->f32
{
    return value * value * (3.0'f32 - 2.0'f32 * value)
}

func lerp(a, b, alpha: f32)->f32
{
    return a + (b - a) * alpha
}

#[Swag.CanOverflow(true)]
func hashGrid(x, y, seed: s32)->u32
{
    var hash = cast(u32) x * 0x9E3779B9'u32
    hash ^= cast(u32) y * 0x85EBCA77'u32
    hash ^= cast(u32) seed * 0xC2B2AE3D'u32
    hash ^= hash >> 16
    hash *= 0x7FEB352D'u32
    hash ^= hash >> 15
    hash *= 0x846CA68B'u32
    hash ^= hash >> 16
    return hash
}

func gridValue(x, y, seed: s32)->f32
{
    let hash = hashGrid(x, y, seed)
    let unit = cast(f32) hash / cast(f32) Swag.U32.Max
    return unit * 2.0'f32 - 1.0'f32
}

func valueNoise(x, y: f32, seed: s32)->f32
{
    let x0 = cast(s32) @floor(x)
    let y0 = cast(s32) @floor(y)
    let tx = smoothStep(x - x0)
    let ty = smoothStep(y - y0)

    let v00 = gridValue(x0, y0, seed)
    let v10 = gridValue(x0 + 1, y0, seed)
    let v01 = gridValue(x0, y0 + 1, seed)
    let v11 = gridValue(x0 + 1, y0 + 1, seed)

    let a = lerp(v00, v10, tx)
    let b = lerp(v01, v11, tx)
    return lerp(a, b, ty)
}

func fractalNoise(x, y: f32, seed: s32)->f32
{
    var amplitude = 1.0'f32
    var frequency = 0.35'f32
    var sum: f32
    var normalizer: f32

    for 4
    {
        let octaveSeed = seed + cast(s32) @index * 131
        sum += valueNoise(x * frequency, y * frequency, octaveSeed) * amplitude
        normalizer += amplitude
        amplitude *= 0.55'f32
        frequency *= 2.0'f32
    }

    return sum / normalizer
}

func buildGardenPlan(seed: u32)->GardenPlanSummary
{
    var rng: GardenRng
    rng.seed(seed)

    let terrainSeed = cast(s32) seed
    let moistureSeed = cast(s32) seed + 911

    var result: GardenPlanSummary

    for row in 3
    {
        let y = cast(f32) row

        for column in 4
        {
            let x = cast(f32) column
            let jitterX = rng.nextF32(-0.35'f32, 0.35'f32)
            let jitterY = rng.nextF32(-0.35'f32, 0.35'f32)
            let terrainHeight = fractalNoise(x + jitterX, y + jitterY, terrainSeed)
            let moistureLevel = fractalNoise(x - jitterY, y + jitterX, moistureSeed)
            let sunlight = rng.nextF32(0.75'f32, 1.25'f32)
            let terrainMark = cast(s32) ((terrainHeight + 1.0'f32) * 1000.0'f32)
            let moistureMark = cast(s32) ((moistureLevel + 1.0'f32) * 1000.0'f32)
            let sunlightMark = cast(s32) (sunlight * 1000.0'f32)
            result.layoutSignature += terrainMark * 3 + moistureMark * 5 + sunlightMark * 7 + row * 11 + column * 13

            if terrainHeight < -0.30'f32
            {
                result.pondPlots += 1
                result.waterReserveLiters += 900
                result.fertilityScore += 1
                continue
            }

            if moistureLevel > 0.35'f32 and sunlight > 0.95'f32
            {
                result.wildflowerPlots += 1
                result.fertilityScore += 6
                if rng.nextBool() do
                    result.compostBins += 1
                continue
            }

            if terrainHeight > 0.45'f32 and moistureLevel < -0.10'f32
            {
                result.stonePathPlots += 1
                result.waterReserveLiters += 120
                if sunlight > 1.10 do
                    result.compostBins += 1
                continue
            }

            result.vegetablePlots += 1
            result.raisedBeds += rng.nextS32(2, 5)
            result.fertilityScore += moistureLevel > 0.10'f32 ? 5 : 3

            if moistureLevel < 0.15'f32 or sunlight > 1.05'f32
            {
                result.irrigatedPlots += 1
                result.waterReserveLiters += 180
            }
            else
            {
                result.waterReserveLiters += 60
            }

            if rng.nextBool() and sunlight > 0.90'f32 do
                result.compostBins += 1
        }
    }

    return result
}

#test
{
    let springLayoutA = buildGardenPlan(0x00C0FFEE'u32)
    let springLayoutB = buildGardenPlan(0x00C0FFEE'u32)
    let autumnLayout = buildGardenPlan(0x0BADF00D'u32)

    @assert(sameSummary(springLayoutA, springLayoutB))
    @assert(sameSummary(springLayoutA, autumnLayout) == false)
    @assert(springLayoutA.layoutSignature != autumnLayout.layoutSignature)

    let totalPlotsA = springLayoutA.pondPlots +
                      springLayoutA.wildflowerPlots +
                      springLayoutA.stonePathPlots +
                      springLayoutA.vegetablePlots

    let totalPlotsB = autumnLayout.pondPlots +
                      autumnLayout.wildflowerPlots +
                      autumnLayout.stonePathPlots +
                      autumnLayout.vegetablePlots

    @assert(totalPlotsA == 12)
    @assert(totalPlotsB == 12)

    @assert(springLayoutA.raisedBeds >= springLayoutA.vegetablePlots * 2)
    @assert(springLayoutA.irrigatedPlots <= springLayoutA.vegetablePlots)
    @assert(springLayoutA.waterReserveLiters >= springLayoutA.pondPlots * 900)
    @assert(springLayoutA.fertilityScore >= springLayoutA.wildflowerPlots * 6)
    @assert(springLayoutA.layoutSignature > 0)

    @assert(autumnLayout.raisedBeds >= autumnLayout.vegetablePlots * 2)
    @assert(autumnLayout.irrigatedPlots <= autumnLayout.vegetablePlots)
    @assert(autumnLayout.waterReserveLiters >= autumnLayout.pondPlots * 900)
    @assert(autumnLayout.compostBins >= 0)
    @assert(autumnLayout.layoutSignature > 0)
}
