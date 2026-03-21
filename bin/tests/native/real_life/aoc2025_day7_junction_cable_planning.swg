#global fileprivate

// Real-life example: plan the shortest junction-box cable runs in a service
// corridor and measure how large the biggest connected circuits become.

struct Point3
{
    x: u32
    y: u32
    z: u32
}

struct Edge
{
    a:      u32
    b:      u32
    dist2:  u64
}

struct CablePlan
{
    pointCount:       u32
    attemptedLinks:   u32
    largestCluster:   u32
    secondCluster:    u32
    thirdCluster:     u32
    topThreeProduct:  u64
}

func absDiff(lhs, rhs: u32)->u32
{
    return lhs > rhs ? lhs - rhs : rhs - lhs
}

func parseNumber(bytes: const [..] u8, index: *u32)->u32
{
    var result: u32

    while dref index < @countof(bytes) and bytes[dref index] >= '0' and bytes[dref index] <= '9'
    {
        result = result * 10'u32 + cast(u32) (bytes[dref index] - '0')
        dref index += 1
    }

    return result
}

func parsePoint(text: string)->Point3
{
    let bytes = cast(const [..] u8) text

    var index: u32
    var result: Point3

    result.x = parseNumber(bytes, &index)
    index += 1
    result.y = parseNumber(bytes, &index)
    index += 1
    result.z = parseNumber(bytes, &index)
    return result
}

func squaredDistance(lhs, rhs: Point3)->u64
{
    let dx = cast(u64) absDiff(lhs.x, rhs.x)
    let dy = cast(u64) absDiff(lhs.y, rhs.y)
    let dz = cast(u64) absDiff(lhs.z, rhs.z)
    return dx * dx + dy * dy + dz * dz
}

func findRoot(parents: const [..] u32, value: u32)->u32
{
    var result = value

    while parents[result] != result
    {
        result = parents[result]
    }

    return result
}

func registerCluster(size: u32, largest: *u32, second: *u32, third: *u32)
{
    if size > dref largest
    {
        dref third = dref second
        dref second = dref largest
        dref largest = size
        return
    }
    if size > dref second
    {
        dref third = dref second
        dref second = size
        return
    }
    if size > dref third do
        dref third = size
}

func planCables(pointLines: const [..] string, attemptedLinks: u32)->CablePlan
{
    @assert(@countof(pointLines) <= 24)

    var points: [24] Point3
    var edges: [320] Edge
    var parents: [24] u32
    var sizes: [24] u32
    var clusterSizes: [24] u32
    var edgeCount: u32

    foreach line, index in pointLines
    {
        points[index] = parsePoint(line)
        parents[index] = cast(u32) index
    }

    for lhs in @countof(pointLines)
    {
        if cast(u32) lhs + 1 >= @countof(pointLines) do
            continue

        for rhs in cast(u32) lhs + 1 to @countof(pointLines) - 1
        {
            edges[edgeCount].a = cast(u32) lhs
            edges[edgeCount].b = cast(u32) rhs
            edges[edgeCount].dist2 = squaredDistance(points[lhs], points[rhs])
            edgeCount += 1
        }
    }

    for edgeIndex in edgeCount
    {
        var bestIndex = edgeIndex

        if edgeIndex + 1 < edgeCount
        {
            for candidate in edgeIndex + 1 to edgeCount - 1
            {
                let best = edges[bestIndex]
                let test = edges[candidate]
                if test.dist2 < best.dist2 or test.dist2 == best.dist2 and (test.a < best.a or test.a == best.a and test.b < best.b)
                {
                    bestIndex = candidate
                }
            }
        }

        if bestIndex != edgeIndex
        {
            let tmp = edges[edgeIndex]
            edges[edgeIndex] = edges[bestIndex]
            edges[bestIndex] = tmp
        }
    }

    let requestedLinks = attemptedLinks < edgeCount ? attemptedLinks : edgeCount

    for edgeIndex in requestedLinks
    {
        let edge = edges[edgeIndex]
        let rootA = findRoot(parents[0 to @countof(pointLines)], edge.a)
        let rootB = findRoot(parents[0 to @countof(pointLines)], edge.b)

        if rootA != rootB do
            parents[rootB] = rootA
    }

    for pointIndex in @countof(pointLines)
    {
        let root = findRoot(parents[0 to @countof(pointLines)], cast(u32) pointIndex)
        sizes[root] += 1
    }

    var result: CablePlan
    result.pointCount = cast(u32) @countof(pointLines)
    result.attemptedLinks = requestedLinks

    for clusterIndex in @countof(pointLines)
    {
        clusterSizes[clusterIndex] = sizes[clusterIndex]
        if clusterSizes[clusterIndex] > 0
        {
            registerCluster(clusterSizes[clusterIndex], &result.largestCluster, &result.secondCluster, &result.thirdCluster)
        }
    }

    result.topThreeProduct = cast(u64) result.largestCluster * cast(u64) result.secondCluster * cast(u64) result.thirdCluster
    return result
}

#test
{
    const samplePoints: [20] string =
    [
        "162,817,812",
        "57,618,57",
        "906,360,560",
        "592,479,940",
        "352,342,300",
        "466,668,158",
        "542,29,236",
        "431,825,988",
        "739,650,466",
        "52,470,668",
        "216,146,977",
        "819,987,18",
        "117,168,530",
        "805,96,715",
        "346,949,466",
        "970,615,88",
        "941,993,340",
        "862,61,35",
        "984,92,344",
        "425,690,689",
    ]

    let samplePlan = planCables(samplePoints, 10)

    @assert(samplePlan.pointCount == 20'u32)
    @assert(samplePlan.attemptedLinks == 10'u32)
    @assert(samplePlan.largestCluster == 5'u32)
    @assert(samplePlan.secondCluster == 4'u32)
    @assert(samplePlan.thirdCluster == 2'u32)
    @assert(samplePlan.topThreeProduct == 40'u64)

    const corridorPoints: [7] string =
    [
        "0,0,0",
        "1,0,0",
        "4,0,0",
        "10,0,0",
        "11,0,0",
        "20,0,0",
        "25,0,0",
    ]

    let corridorPlan = planCables(corridorPoints, 5)

    @assert(corridorPlan.pointCount == 7'u32)
    @assert(corridorPlan.attemptedLinks == 5'u32)
    @assert(corridorPlan.largestCluster == 3'u32)
    @assert(corridorPlan.secondCluster == 2'u32)
    @assert(corridorPlan.thirdCluster == 2'u32)
    @assert(corridorPlan.topThreeProduct == 12'u64)
}
