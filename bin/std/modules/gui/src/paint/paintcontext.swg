using Core, Pixel

// Represents paint context.
public struct PaintContext
{
    painter:    *Painter   = undefined // Painter associated with this value.
    renderer:   *RenderOgl = undefined // Renderer associated with this value.
    isDisabled: bool // Whether this value is disabled.
}
