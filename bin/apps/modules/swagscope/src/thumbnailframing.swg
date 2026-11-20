using Core, Pixel, Gui

// The nominal tile aspect chooses a cached placement independently of layout rounding.
enum ThumbnailShape
{
    Grid
    Wide
    Poster
    Square
    HomeHero
}

const ThumbnailCropModes = [Image.SmartCropMode.Attention, .Entropy, .Center, .None]

func thumbnailCropNames()->[4] string
{
    let text = appStrings()
    return [text.crop_Attention, text.crop_Entropy, text.crop_Center, text.crop_None]
}

// Relative placement along the trim axis, encoded once for the shapes Scope can display.
struct ThumbnailFraming
{
    private offsets: [2, 5] u8
    private valid:   bool
}

impl ThumbnailFraming
{
    private const Tag = "scope.thumbnail.crop"
    private const Aspects = [1.0 / ExplorerGrid.TileAspect, 1.0 / ExplorerFilmTileAspect,
                             1.0 / ExplorerGrid.PosterAspect, 1.0'f32, ViewerHome.HeroWidth / ViewerHome.HeroHeight]

    func analyze(image: const *Image)->ThumbnailFraming
    {
        var result: #returntype
        let width  = cast(f32, image.width)
        let height = cast(f32, image.height)
        for mode in 2
        {
            for aspect, shape in Aspects
            {
                let rect = image.smartCropRect(aspect, ThumbnailCropModes[mode])
                let room = Math.max(width - rect.width, height - rect.height)
                let at   = room > 0 ? (rect.x + rect.y) / room : 0.5
                result.offsets[mode, shape] = cast(u8, Math.round(Math.saturate(at) * 255))
            }
        }

        result.valid = true
        return result
    }

    func labelImage(image: *Image)
    {
        if not image.isValid() or (image.width == 1 and image.height == 1) or Swag.isCancelled() do
            return
        let framing = analyze(image)
        var record: ImageMetadata
        var text: String
        for mode in 2
        {
            for shape in Aspects.count do
                text += Format.toString("%{X02}", framing.offsets[mode, shape])
        }

        record.tag   = Tag
        record.value = text.toString()
        for &previous in image.metadata where previous.isTag(cast(const [..] u8, Tag))
        {
            previous[] = #move record
            return
        }
        image.metadata.add(#move record)
    }

    func fromImage(image: const *Image)->ThumbnailFraming
    {
        func digit(value: u8)->u8 => value <= '9' ? value - '0'u8 : value - 'A'u8 + 10

        for &record in image.metadata where record.isTag(cast(const [..] u8, Tag))
        {
            let text = cast(string, record.toSlice())
            if text.count != 4 * Aspects.count do
                continue
            for byte in text where not Latin1.isDigit(byte) and (byte < 'A' or byte > 'F') do
                return {}

            var result: #returntype
            for mode in 2
            {
                for shape in Aspects.count
                {
                    let index = (mode * Aspects.count + shape) * 2
                    result.offsets[mode, shape] = digit(text[index]) * 16 + digit(text[index + 1])
                }
            }
            result.valid = true
            return result
        }

        return {}
    }

    mtd const crop(width, height, aspect: f32, shape: ThumbnailShape, mode: Image.SmartCropMode)->Math.Rectangle
    {
        if mode == .None do
            return {0, 0, width, height}
        let cropWidth  = Math.min(width, height * aspect)
        let cropHeight = Math.min(height, width / aspect)
        let index      = cast(u64, mode)
        let offset     = .valid and index < 2 ? cast(f32, .offsets[index, cast(u64, shape)]) / 255 : 0.5
        return {(width - cropWidth) * offset, (height - cropHeight) * offset, cropWidth, cropHeight}
    }

    mtd const paint(host: *Wnd, painter: *Painter, texture: Texture, tile: Math.Rectangle,
                    shape: ThumbnailShape, mode: Image.SmartCropMode)
    {
        var brush    = Brush.createTexture(texture)
        brush.uvMode = .FillSubRect
        brush.uvRect = .crop(cast(f32, texture.width), cast(f32, texture.height), tile.width / tile.height, shape, mode)
        let radius   = host.themeMetrics().corner_Control
        painter.fillRoundRect(tile, radius, radius, brush)
    }
}
