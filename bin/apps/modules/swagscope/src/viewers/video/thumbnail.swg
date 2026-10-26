#global internal
#global namespace Viewers.Film

using Core, Pixel, Video

// A small RGB histogram describes the picture without retaining a full-resolution frame.
struct ThumbnailCandidate
{
    image:     Image
    histogram: [48] f32
    usable:    bool
    lively:    bool     // Contrasted and mostly lit, which a viewer reads as a scene rather than a transition.
}

impl ThumbnailCandidate
{
    mtd analyze()
    {
        var black, white, samples: u32
        var lumaSum, lumaSquares: f32
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
                lumaSum     += cast(f32, luma)
                lumaSquares += cast(f32, luma * luma)
                .histogram[color.r / 16]      += 1
                .histogram[16 + color.g / 16] += 1
                .histogram[32 + color.b / 16] += 1
                samples += 1
            }
        }

        .usable = black * 100 < samples * 98 and white * 100 < samples * 98

        let mean     = lumaSum / cast(f32, samples)
        let variance = lumaSquares / cast(f32, samples) - mean * mean
        .lively = .usable and black * 100 < samples * 60 and variance >= 24 * 24
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

// Positions tried, as fractions of the duration, in order of preference.
//
// A third of the way in is past the opening titles and rarely a transition. Every position costs
// a seek and a decoded picture, which across a network share is most of a thumbnail, so the first
// lively picture is kept and the others are only fallbacks for a dark or blank frame there. Each
// is read as a key picture: the clean point the container indexes near it, read alone.
const ThumbnailPositions: [5] f64 = [0.3, 0.5, 0.15, 0.7, 0.9]

func loadThumbnail(fileName: string, maxSide: u32 = 256)->Image fail
{
    var reader   = try Reader.open(fileName, pictureOnly: true)
    var candidates: Array'ThumbnailCandidate
    var previous = -1.0'f64
    let duration = reader.durationInSeconds()
    for fraction in ThumbnailPositions
    {
        if Swag.isCancelled() do
            break

        // Without a duration every position is the start of the stream.
        let seconds = duration * fraction
        if seconds == previous do
            continue
        previous = seconds

        var candidate: ThumbnailCandidate
        candidate.image = catch reader.decodeKeyPicture(seconds) { continue }
        let largest = Math.max(candidate.image.width, candidate.image.height)
        if largest > maxSide
        {
            let scale = cast(f32, maxSide) / cast(f32, largest)
            candidate.image.resize(Math.max(1, cast(s32, cast(f32, candidate.image.width) * scale)),
                                   Math.max(1, cast(s32, cast(f32, candidate.image.height) * scale)),
                                   .Bilinear)
        }

        trimLetterbox(&candidate.image)
        candidate.analyze()
        if candidate.lively
        {
            labelDuration(&candidate.image, duration)
            return #move candidate.image
        }

        candidates.add(#move candidate)
    }

    if candidates.isEmpty() do
        fail Errors.InvalidFormatError{}
    let selected = representativeThumbnail(candidates.toSlice())
    labelDuration(&candidates[selected].image, duration)
    return #move candidates[selected].image
}

// Trims the black bands a film was encoded with, so the thumbnail shows the picture rather than the
// letterbox or pillarbox around it.
//
// A band is a run of near-black rows or columns at an edge. A frame dark across more than a quarter
// from an edge is a dark scene rather than a band, and is left whole.
func trimLetterbox(image: *Image)
{
    let width  = image.width
    let height = image.height
    let top    = bandDepth(image, height / 4, func(image: const *Image, depth, sample: s32)->Color => image.pixelColor(sample * image.width / 32, depth))
    let bottom = bandDepth(image, height / 4, func(image: const *Image, depth, sample: s32)->Color => image.pixelColor(sample * image.width / 32, image.height - 1 - depth))
    let left   = bandDepth(image, width / 4, func(image: const *Image, depth, sample: s32)->Color => image.pixelColor(depth, sample * image.height / 32))
    let right  = bandDepth(image, width / 4, func(image: const *Image, depth, sample: s32)->Color => image.pixelColor(image.width - 1 - depth, sample * image.height / 32))
    if top + bottom + left + right == 0 do
        return
    image.crop(left, top, width - left - right, height - top - bottom)
}

// Returns how many lines from one edge are near black, or zero when the run reaches `limit`.
private func bandDepth(image: const *Image, limit: s32, sampleAt: func(const *Image, s32, s32)->Color)->s32
{
    var depth = 0
    while depth < limit
    {
        for sample in 32
        {
            let color = sampleAt(image, depth, sample)
            if color.r > 24 or color.g > 24 or color.b > 24 do
                return depth
        }

        depth += 1
    }

    return 0
}

// Labels a thumbnail with the duration of its film, when the container states one.
private func labelDuration(image: *Image, seconds: f64)
{
    if seconds < 1 do
        return
    var record: ImageMetadata
    record.tag   = Viewer.ThumbnailDurationTag
    record.value = Format.toString("%", cast(u64, seconds))
    image.metadata.add(#move record)
}
