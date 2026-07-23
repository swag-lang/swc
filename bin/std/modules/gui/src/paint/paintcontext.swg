using Core, Pixel

public struct PaintContext
{
    painter:    *Painter = undefined
    renderer:   *RenderOgl = undefined
    isDisabled: bool
}
