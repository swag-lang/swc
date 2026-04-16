#global fileprivate

struct(T) Range
    where T == f32 or T == f64
{
    min: T
    max: T
}

func(T) clampToRange(value: T, bounds: Range'T)->T
    where T == f32 or T == f64
{
    if value < bounds.min do
        return bounds.min
    if value > bounds.max do
        return bounds.max
    return value
}

func(T, U = T) lerp(a: T, b: U, ratio: T)->T
    where T == U
    where T == f32 or T == f64
{
    return a + (b - a) * ratio
}

#[Swag.Overload]
func(T) severity(delta: T)->u8
    where T == s32 or T == s64
{
    if delta >= 50 do
        return 3
    if delta >= 10 do
        return 2
    return 1
}

#[Swag.Overload]
func(T) severity(delta: T)->u8
    where T == f32 or T == f64
{
    if delta >= 5.0 do
        return 3
    if delta >= 1.0 do
        return 2
    return 1
}

struct(T, Count: s32) MovingWindow
    where Count > 0
    where T == f32 or T == f64
{
    values: [Count] T
    next: s32
    filled: s32
}

impl MovingWindow
{
    func push(me, value: T)
    {
        .values[.next] = value
        .next = (.next + 1) % Count
        if .filled < Count do
            .filled += 1
    }

    func(const Index: s32) at(const me)->T
        where Index >= 0
        where Index < Count
    {
        return .values[Index]
    }

    func(U = T) echoTyped(const me, value: U)->U
        where T == U
    {
        return value
    }

    func average(const me)->T
        where Count >= 2
    {
        var total: T = 0
        for var i = 0; i < .filled; i += 1 do
            total += .values[i]
        return total / cast(T) .filled
    }
}

struct(T, Count: s32) SensorChannel
    where Count > 0
    where T == f32 or T == f64
{
    scale: T
    offset: T
    safe: Range'T
    window: MovingWindow'(T, Count)
}

impl SensorChannel
{
    func ingest(me, raw: T)->T
    {
        let adjusted = clampToRange(raw * .scale + .offset, .safe)
        .window.push(adjusted)
        return adjusted
    }

    func(U = T) deviation(const me, baseline: U)->T
        where T == U
    {
        return .window.average() - baseline
    }

    func latest(const me)->T
        where Count > 0
    {
        let index = (.window.next + Count - 1) % Count
        return .window.values[index]
    }
}

#test
{
    let safe: Range'f64 = {min: -10.0, max: 10.0}
    @assert(clampToRange(-15.0'f64, safe) == -10.0'f64)
    @assert(clampToRange(6.0'f64, safe) == 6.0'f64)
    @assert(clampToRange(15.0'f64, safe) == 10.0'f64)

    @assert(lerp(10.0'f64, 20.0'f64, 0.25'f64) == 12.5'f64)

    @assert(severity(5's32) == 1)
    @assert(severity(15's64) == 2)
    @assert(severity(1.5'f32) == 2)
    @assert(severity(8.0'f64) == 3)
}

#test
{
    var window: MovingWindow'(f32, 3) = {values: [0.0'f32, 0.0, 0.0], next: 0, filled: 0}

    window.push(10.0)
    window.push(20.0)
    window.push(30.0)

    @assert(window.at'1() == 20.0'f32)
    @assert(window.echoTyped(99.0'f32) == 99.0'f32)
    @assert(window.average() == 20.0'f32)

    window.push(40.0)
    @assert(window.at'0() == 40.0'f32)
    @assert(window.average() == 30.0'f32)
}

#test
{
    var channel: SensorChannel'(f32, 2) =
    {
        scale: 1.0,
        offset: 0.0,
        safe: {min: 0.0, max: 100.0},
        window: {values: [0.0'f32, 0.0], next: 0, filled: 0},
    }

    @assert(channel.ingest(10.0'f32) == 10.0'f32)
    @assert(channel.ingest(150.0'f32) == 100.0'f32)
    @assert(channel.latest() == 100.0'f32)
    @assert(channel.window.average() == 55.0'f32)
    @assert(channel.deviation(50.0'f32) == 5.0'f32)
}
