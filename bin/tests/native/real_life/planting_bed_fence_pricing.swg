#global fileprivate

// Real-life example: price fencing for contiguous planting beds using both raw
// perimeter length and a discounted side-count estimate.

struct FencePricingReport
{
    regionCount:          u32
    totalPerimeterPrice:  u64
    totalDiscountedPrice: u64
}

func lineWidth(line: string)->u32
{
    return cast(u32) @countof(cast(const [..] u8) line)
}

func cellIndex(x, y, width: u32)->u32
{
    return y * width + x
}

func cropAt(layout: const [..] string, x, y: u32)->u8
{
    let row = cast(const [..] u8) layout[y]
    return row[x]
}

func analyzeFencePricing(layout: const [..] string)->FencePricingReport
{
    let height = cast(u32) @countof(layout)
    let width = lineWidth(layout[0])
    let totalCells = width * height

    @assert(height > 0)
    @assert(width > 0)
    @assert(totalCells <= 400)

    var visited: [400] bool
    var inRegion: [400] bool
    var queue: [400] u32
    var regionCells: [400] u32
    var result: FencePricingReport

    foreach _, rowIndex in layout
    {
        @assert(lineWidth(layout[rowIndex]) == width)
    }

    for totalCells
    {
        let startIndex = cast(u32) @index
        if visited[startIndex] do
            continue

        let startX = startIndex % width
        let startY = startIndex / width
        let crop = cropAt(layout, startX, startY)

        var head: u32
        var tail: u32
        var regionCount: u32

        visited[startIndex] = true
        queue[tail] = startIndex
        tail += 1

        while head < tail
        {
            let current = queue[head]
            head += 1

            regionCells[regionCount] = current
            regionCount += 1
            inRegion[current] = true

            let x = current % width
            let y = current / width

            if x + 1 < width
            {
                let next = cellIndex(x + 1, y, width)
                if !visited[next] and cropAt(layout, x + 1, y) == crop
                {
                    visited[next] = true
                    queue[tail] = next
                    tail += 1
                }
            }

            if x > 0
            {
                let next = cellIndex(x - 1, y, width)
                if !visited[next] and cropAt(layout, x - 1, y) == crop
                {
                    visited[next] = true
                    queue[tail] = next
                    tail += 1
                }
            }

            if y + 1 < height
            {
                let next = cellIndex(x, y + 1, width)
                if !visited[next] and cropAt(layout, x, y + 1) == crop
                {
                    visited[next] = true
                    queue[tail] = next
                    tail += 1
                }
            }

            if y > 0
            {
                let next = cellIndex(x, y - 1, width)
                if !visited[next] and cropAt(layout, x, y - 1) == crop
                {
                    visited[next] = true
                    queue[tail] = next
                    tail += 1
                }
            }
        }

        result.regionCount += 1

        var perimeter: u32
        var sideCount: u32

        for regionCount
        {
            let current = regionCells[@index]
            let x = current % width
            let y = current / width

            let leftInRegion = x > 0 and inRegion[cellIndex(x - 1, y, width)]
            let rightInRegion = x + 1 < width and inRegion[cellIndex(x + 1, y, width)]
            let topInRegion = y > 0 and inRegion[cellIndex(x, y - 1, width)]
            let bottomInRegion = y + 1 < height and inRegion[cellIndex(x, y + 1, width)]
            let topLeftInRegion = x > 0 and y > 0 and inRegion[cellIndex(x - 1, y - 1, width)]
            let topRightInRegion = x + 1 < width and y > 0 and inRegion[cellIndex(x + 1, y - 1, width)]
            let bottomLeftInRegion = x > 0 and y + 1 < height and inRegion[cellIndex(x - 1, y + 1, width)]

            let exposedTop = !topInRegion
            let exposedBottom = !bottomInRegion
            let exposedLeft = !leftInRegion
            let exposedRight = !rightInRegion

            if exposedTop do
                perimeter += 1
            if exposedBottom do
                perimeter += 1
            if exposedLeft do
                perimeter += 1
            if exposedRight do
                perimeter += 1

            if exposedTop and (!leftInRegion or topLeftInRegion) do
                sideCount += 1
            if exposedBottom and (!leftInRegion or bottomLeftInRegion) do
                sideCount += 1
            if exposedLeft and (!topInRegion or topLeftInRegion) do
                sideCount += 1
            if exposedRight and (!topInRegion or topRightInRegion) do
                sideCount += 1
        }

        result.totalPerimeterPrice += cast(u64) regionCount * cast(u64) perimeter
        result.totalDiscountedPrice += cast(u64) regionCount * cast(u64) sideCount

        for regionCount
        {
            inRegion[regionCells[@index]] = false
        }
    }

    return result
}

#test
{
    const sampleBeds: [4] string =
    [
        "AAAA",
        "BBCD",
        "BBCC",
        "EEEC",
    ]

    let sampleReport = analyzeFencePricing(sampleBeds)

    @assert(sampleReport.regionCount == 5'u32)
    @assert(sampleReport.totalPerimeterPrice == 140'u64)
    @assert(sampleReport.totalDiscountedPrice == 80'u64)

    const courtyardBeds: [4] string =
    [
        "AAAA",
        "ABBA",
        "ABBA",
        "AAAA",
    ]

    let courtyardReport = analyzeFencePricing(courtyardBeds)

    @assert(courtyardReport.regionCount == 2'u32)
    @assert(courtyardReport.totalPerimeterPrice == 320'u64)
    @assert(courtyardReport.totalDiscountedPrice == 112'u64)
}
