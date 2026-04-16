#global fileprivate

// A telemetry pipeline where `where` constraints keep math on floating-point
// channels, gate fixed-size algorithms by compile-time window sizes, and make
// unit-specific helper methods reject mixed units before code is generated.

struct Celsius {}
struct PercentHumidity {}
struct Kilopascal {}

struct(T) SafeBand
    where T == f32 or T == f64
{
    low: T
    high: T
}

func(T) clampToBand(value: T, band: SafeBand'T)->T
    where T == f32 or T == f64
{
    if value < band.low do
        return band.low
    if value > band.high do
        return band.high
    return value
}

func(T, U = T) interpolate(a: T, b: U, ratio: T)->T
    where T == U
    where T == f32 or T == f64
{
    return a + (b - a) * ratio
}

struct(Unit, T, Count: s32) TelemetrySeries
    where Count >= 2
    where T == f32 or T == f64
{
    name: string
    scale: T
    offset: T
    band: SafeBand'T
    samples: [Count] T
    next: s32
    filled: s32
}

impl TelemetrySeries
{
    func ingest(me, raw: T)->T
    {
        let calibrated = clampToBand(raw * .scale + .offset, .band)
        .samples[.next] = calibrated
        .next = (.next + 1) % Count
        if .filled < Count do
            .filled += 1
        return calibrated
    }

    func(const Index: s32) sample(const me)->T
        where Index >= 0
        where Index < Count
    {
        return .samples[Index]
    }

    func average(const me)->T
        where Count >= 2
    {
        var total: T = 0
        for var i = 0; i < .filled; i += 1 do
            total += .samples[i]
        return total / cast(T) .filled
    }

    func movingMidpoint(const me)->T
        where Count >= 3
    {
        let oldestIndex = .next % Count
        let newestIndex = (.next + Count - 1) % Count
        return interpolate(.samples[oldestIndex], .samples[newestIndex], cast(T) 0.5)
    }

    func(U = Unit) sameUnit(const me, other: U)->bool
        where Unit == U
    {
        return true
    }

    func(U = T) drift(const me, baseline: U)->T
        where T == U
    {
        return .average() - baseline
    }

    func(U = T) midpoint(const me, left: U, right: U)->T
        where T == U
    {
        return interpolate(left, right, cast(T) 0.5)
    }
}

#test
{
    var temperature: TelemetrySeries'(Celsius, f32, 3) =
    {
        name: "temperature",
        scale: 1.0,
        offset: 0.0,
        band: {low: -40.0, high: 120.0},
        samples: [0.0'f32, 0.0, 0.0],
        next: 0,
        filled: 0,
    }

    @assert(temperature.ingest(18.0'f32) == 18.0'f32)
    @assert(temperature.ingest(21.0'f32) == 21.0'f32)
    @assert(temperature.ingest(24.0'f32) == 24.0'f32)

    @assert(temperature.sample'0() == 18.0'f32)
    @assert(temperature.average() == 21.0'f32)
    @assert(temperature.movingMidpoint() == 21.0'f32)
    @assert(temperature.sameUnit(Celsius{}))
    @assert(temperature.drift(20.0'f32) == 1.0'f32)
    @assert(temperature.midpoint(12.0'f32, 16.0'f32) == 14.0'f32)
}

#test
{
    var temperature: TelemetrySeries'(Celsius, f32, 3) =
    {
        name: "temperature",
        scale: 1.0,
        offset: 0.0,
        band: {low: -40.0, high: 120.0},
        samples: [18.0'f32, 21.0, 24.0],
        next: 0,
        filled: 3,
    }

    @assert(temperature.ingest(30.0'f32) == 30.0'f32)
    @assert(temperature.sample'0() == 30.0'f32)
    @assert(temperature.average() == 25.0'f32)
    @assert(temperature.movingMidpoint() == 25.5'f32)
}

#test
{
    var humidity: TelemetrySeries'(PercentHumidity, f64, 4) =
    {
        name: "humidity",
        scale: 1.0,
        offset: 0.0,
        band: {low: 0.0, high: 100.0},
        samples: [0.0'f64, 0.0, 0.0, 0.0],
        next: 0,
        filled: 0,
    }

    @assert(humidity.ingest(40.0'f64) == 40.0'f64)
    @assert(humidity.ingest(55.0'f64) == 55.0'f64)
    @assert(humidity.ingest(72.0'f64) == 72.0'f64)
    @assert(humidity.ingest(88.0'f64) == 88.0'f64)

    @assert(humidity.average() == 63.75'f64)
    @assert(humidity.midpoint(50.0'f64, 90.0'f64) == 70.0'f64)
}

#test
{
    var pressure: TelemetrySeries'(Kilopascal, f64, 3) =
    {
        name: "pressure",
        scale: 0.1,
        offset: 90.0,
        band: {low: 90.0, high: 110.0},
        samples: [0.0'f64, 0.0, 0.0],
        next: 0,
        filled: 0,
    }

    @assert(pressure.ingest(40.0'f64) == 94.0'f64)
    @assert(pressure.ingest(100.0'f64) == 100.0'f64)
    @assert(pressure.ingest(160.0'f64) == 106.0'f64)
    @assert(pressure.average() == 100.0'f64)
    @assert(pressure.movingMidpoint() == 100.0'f64)
}
