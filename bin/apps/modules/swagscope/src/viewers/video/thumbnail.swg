#global internal
#global namespace Viewers.Film

using Core, Pixel, Video

// A small RGB histogram describes the picture without retaining a full-resolution frame.
struct ThumbnailCandidate
{
    image:     Image
    histogram: [48] f32
    usable:    bool
}

impl ThumbnailCandidate
{
    mtd analyze()
    {
        var black, white, samples: u32
        for y in 24
        {
            for x in 32
            {
                let color = .image.pixelColor(x * .image.width / 32, y * .image.height / 24)
                let luma  = (77 * cast(u32, color.r) + 150 * cast(u32, color.g) + 29 * cast(u32, color.b)) / 256
                if luma < 32 do
                    black += 1
                if luma > 240 do
                    white += 1
                .histogram[color.r / 16]      += 1
                .histogram[16 + color.g / 16] += 1
                .histogram[32 + color.b / 16] += 1
                samples += 1
            }
        }

        .usable = black * 100 < samples * 98 and white * 100 < samples * 98
    }
}

// Pick the histogram nearest the usable sample mean, excluding fades to black or white.
func representativeThumbnail(candidates: const [..] ThumbnailCandidate)->u64
{
    var average: [48] f32
    var count:   f32
    for &candidate in candidates where candidate.usable
    {
        for bin in average.count do
            average[bin] += candidate.histogram[bin]
        count += 1
    }

    if count == 0 do
        return 0
    for bin in average.count do
        average[bin] /= count

    var best     = 0'u64
    var distance = Swag.F32.Max
    for &candidate, index in candidates where candidate.usable
    {
        var score: f32
        for bin in average.count
        {
            let delta = candidate.histogram[bin] - average[bin]
            score += delta * delta
        }

        if score < distance
        {
            best     = index
            distance = score
        }
    }

    return best
}

func loadThumbnail(fileName: string, maxSide: u32 = 256)->Image fail
{
    var reader   = try Reader.open(fileName, pictureOnly: true)
    var candidates: Array'ThumbnailCandidate
    var previous = Swag.U64.Max
    let duration = reader.durationInSeconds()
    for fraction in [0.1, 0.3, 0.5, 0.7, 0.9]
    {
        if Swag.isCancelled() do
            break
        let count  = reader.frameCount()
        let target = duration > 0 ? reader.frameAtTime(duration * fraction) : cast(u64, candidates.count)
        var index  = count ? Math.min(target, count - 1) : target
        let sync   = reader.syncFrameAt(index)
        if sync >= index and (not count or sync < count) do
            index = sync
        if index == previous do
            continue
        previous = index

        var candidate: ThumbnailCandidate
        candidate.image = catch reader.decodeFrame(index) { continue }
        let largest = Math.max(candidate.image.width, candidate.image.height)
        if largest > maxSide
        {
            let scale = cast(f32, maxSide) / cast(f32, largest)
            candidate.image.resize(Math.max(1, cast(s32, cast(f32, candidate.image.width) * scale)),
                                   Math.max(1, cast(s32, cast(f32, candidate.image.height) * scale)),
                                   .Bilinear)
        }

        candidate.analyze()
        candidates.add(#move candidate)
    }

    if candidates.isEmpty() do
        fail Errors.InvalidFormatError{}
    let selected = representativeThumbnail(candidates.toSlice())
    return #move candidates[selected].image
}
