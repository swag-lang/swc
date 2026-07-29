using Core

impl Image
{
    // Bit mask selecting destination channels for [[Image.setChannel]].
    #[Swag.EnumFlags]
    public enum ChannelMode
    {
        Red               // Red channel.
        Green             // Green channel.
        Blue              // Blue channel.
        Alpha             // Alpha channel.
        RGB  = Red | Green | Blue // All color channels.
        RGBA = RGB | Alpha        // All color and alpha channels.
    }

    // Selects the value copied into channels by [[Image.setChannel]].
    public enum ChannelValueMode
    {
        Color   // Use the explicit `color` byte.
        MinRGB  // Use the smallest color channel of the current pixel.
        MaxRGB  // Use the largest color channel of the current pixel.
        MeanRGB // Use the arithmetic mean of the current color channels.
        Alpha   // Use the current alpha channel.
    }

    // Change the alpha channel
    public mtd setAlpha(value: u8 = 0)
    {
        if .pf != .BGRA8 do
            return
        .setChannel(Image.ChannelMode.Alpha, Image.ChannelValueMode.Color, value)
    }

    // Change specified color channels
    public mtd setChannel(mode: ChannelMode, value: ChannelValueMode, color: u8 = 0)
    {
        if .pf != .BGR8 and .pf != .BGRA8 do
            return

        // Remove alpha change if it does not exists
        var rmode = mode
        if .pf == .BGR8
        {
            rmode &= ~.Alpha
            if rmode == 0 or value == .Alpha do
                return
        }

        var f = {rmode: rmode, value: value, color: color}
        .visitPixels(&f)
        {
            let params = cast(*#decltype(f)) (notnull userData)
            let mode   = params.rmode

            var channelValue: u8 = undefined
            switch #complete params.value
            {
            case .Color:   channelValue = params.color
            case .MinRGB:  channelValue = Math.min(pix[0], pix[1], pix[2])
            case .MaxRGB:  channelValue = Math.max(pix[0], pix[1], pix[2])
            case .MeanRGB: channelValue = cast(u8) ((pix[0] + #prom pix[1] + #prom pix[2]) / 3)
            case .Alpha:   channelValue = pix[3]
            }

            if mode & .Blue do
                pix[0] = channelValue
            if mode & .Green do
                pix[1] = channelValue
            if mode & .Red do
                pix[2] = channelValue
            if mode & .Alpha do
                pix[3] = channelValue
        }
    }
}
