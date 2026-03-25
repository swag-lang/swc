#global fileprivate

// Advent of Code 2024 Day 8: find antinode positions created by same-frequency
// antenna pairs, using heap-allocated storage and reference types for mutation.

const MaxFrequencies = 128'u32
const MaxAntennasPerFreq = 32'u32

const SampleInput =
"""............
........0...
.....0......
.......0....
....0.......
......A.....
............
............
........A...
.........A..
............
............"""

const SmallInput =
"""..........
...#......
..........
....a.....
..........
.....a....
..........
......#...
..........
.........."""

const TwoFreqInput =
"""..........
...#......
#.........
....a.....
........a.
.....a....
..#.......
......A...
..........
.........."""

struct Vec2
{
    x: s32
    y: s32
}

struct AntennaGroup
{
    count:     u32
    positions: [MaxAntennasPerFreq] Vec2
}

struct AntennaMap
{
    width:     u32
    height:    u32
    groups:    [MaxFrequencies] AntennaGroup
    freqUsed:  [MaxFrequencies] bool
}

struct AntinodeGrid
{
    width:  u32
    height: u32
    cells:  [*] u8
}

struct ResonanceReport
{
    width:              u32
    height:             u32
    antennaCount:       u32
    frequencyCount:     u32
    simpleAntinodes:    u32
    harmonicAntinodes:  u32
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func isLineBreak(ch: u8)->bool
{
    return ch == '\n''u8 or ch == '\r''u8
}

func isAntenna(ch: u8)->bool
{
    return (ch >= '0' and ch <= '9') or
           (ch >= 'A' and ch <= 'Z') or
           (ch >= 'a' and ch <= 'z')
}

// ---------------------------------------------------------------------------
// AntinodeGrid: heap-allocated boolean grid with reference-based API
// ---------------------------------------------------------------------------

func initAntinodeGrid(width, height: u32)->AntinodeGrid
{
    var result: AntinodeGrid
    result.width = width
    result.height = height
    let size = cast(u64) width * cast(u64) height
    result.cells = cast([*] u8) @alloc(size)
    @assert(result.cells != null)
    for width * height
    {
        result.cells[cast(u32) @index] = 0'u8
    }
    return result
}

func freeAntinodeGrid(grid: AntinodeGrid)
{
    if grid.cells do
        @free(grid.cells)
}

func markAntinode(grid: &AntinodeGrid, x, y: s32)->bool
{
    if x < 0 or y < 0 or cast(u32) x >= grid.width or cast(u32) y >= grid.height do
        return false

    let idx = cast(u32) y * grid.width + cast(u32) x
    let isNew = grid.cells[idx] == 0'u8
    grid.cells[idx] = 1'u8
    return isNew
}

func clearGrid(grid: &AntinodeGrid)
{
    for grid.width * grid.height
    {
        grid.cells[cast(u32) @index] = 0'u8
    }
}

func countMarked(grid: const &AntinodeGrid)->u32
{
    var count: u32
    for grid.width * grid.height
    {
        if grid.cells[cast(u32) @index] != 0'u8 do
            count += 1
    }
    return count
}

// ---------------------------------------------------------------------------
// Parsing: fills an AntennaMap through a mutable reference
// ---------------------------------------------------------------------------

func parseAntennaMap(result: &AntennaMap, text: string)
{
    let bytes = cast(const [..] u8) text

    var width: u32
    while width < @countof(bytes) and !isLineBreak(bytes[width])
    {
        width += 1
    }

    result.width = width

    var x: u32
    var y: u32
    for @countof(bytes)
    {
        let ch = bytes[@index]
        if isLineBreak(ch)
        {
            if x > 0
            {
                @assert(x == width)
                y += 1
                x = 0
            }
            continue
        }

        if isAntenna(ch)
        {
            let freq = cast(u32) ch
            @assert(freq < MaxFrequencies)
            let group = &result.groups[freq]
            @assert(group.count < MaxAntennasPerFreq)
            group.positions[group.count] = {x: cast(s32) x, y: cast(s32) y}
            group.count += 1
            result.freqUsed[freq] = true
        }

        x += 1
    }

    if x > 0 do
        y += 1

    result.height = y
}

func countAntennas(map: const &AntennaMap)->u32
{
    var total: u32
    for MaxFrequencies
    {
        total += map.groups[cast(u32) @index].count
    }
    return total
}

func countFrequencies(map: const &AntennaMap)->u32
{
    var total: u32
    for MaxFrequencies
    {
        if map.freqUsed[cast(u32) @index] do
            total += 1
    }
    return total
}

// ---------------------------------------------------------------------------
// Antinode computation
// ---------------------------------------------------------------------------

func computeSimpleAntinodes(grid: &AntinodeGrid, map: const &AntennaMap)
{
    for MaxFrequencies
    {
        let freq = cast(u32) @index
        if !map.freqUsed[freq] do
            continue

        let group = &map.groups[freq]
        for a in group.count
        {
            for b in group.count
            {
                if a == b do
                    continue

                let pa = group.positions[a]
                let pb = group.positions[b]
                let dx = pb.x - pa.x
                let dy = pb.y - pa.y

                discard markAntinode(grid, pa.x - dx, pa.y - dy)
            }
        }
    }
}

func computeHarmonicAntinodes(grid: &AntinodeGrid, map: const &AntennaMap)
{
    for MaxFrequencies
    {
        let freq = cast(u32) @index
        if !map.freqUsed[freq] do
            continue

        let group = &map.groups[freq]
        for a in group.count
        {
            for b in group.count
            {
                if a == b do
                    continue

                let pa = group.positions[a]
                let pb = group.positions[b]
                let dx = pb.x - pa.x
                let dy = pb.y - pa.y

                var cx = pa.x
                var cy = pa.y
                while cx >= 0 and cy >= 0 and cast(u32) cx < grid.width and cast(u32) cy < grid.height
                {
                    discard markAntinode(grid, cx, cy)
                    cx -= dx
                    cy -= dy
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

func analyzeResonance(text: string)->ResonanceReport
{
    var map: AntennaMap
    parseAntennaMap(&map, text)

    var grid = initAntinodeGrid(map.width, map.height)
    defer freeAntinodeGrid(grid)

    var result: ResonanceReport
    result.width = map.width
    result.height = map.height
    result.antennaCount = countAntennas(&map)
    result.frequencyCount = countFrequencies(&map)

    computeSimpleAntinodes(&grid, &map)
    result.simpleAntinodes = countMarked(&grid)

    clearGrid(&grid)

    computeHarmonicAntinodes(&grid, &map)
    result.harmonicAntinodes = countMarked(&grid)

    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#test
{
    let sample = analyzeResonance(SampleInput)

    @assert(sample.width == 12'u32)
    @assert(sample.height == 12'u32)
    @assert(sample.antennaCount == 7'u32)
    @assert(sample.frequencyCount == 2'u32)
    @assert(sample.simpleAntinodes == 14'u32)
    @assert(sample.harmonicAntinodes == 34'u32)
}

#test
{
    let small = analyzeResonance(SmallInput)

    @assert(small.width == 10'u32)
    @assert(small.height == 10'u32)
    @assert(small.antennaCount == 2'u32)
    @assert(small.frequencyCount == 1'u32)
    @assert(small.simpleAntinodes == 2'u32)
    @assert(small.harmonicAntinodes == 5'u32)
}

#test
{
    let twoFreq = analyzeResonance(TwoFreqInput)

    @assert(twoFreq.width == 10'u32)
    @assert(twoFreq.height == 10'u32)
    @assert(twoFreq.antennaCount == 4'u32)
    @assert(twoFreq.frequencyCount == 2'u32)
    @assert(twoFreq.simpleAntinodes == 4'u32)
}
