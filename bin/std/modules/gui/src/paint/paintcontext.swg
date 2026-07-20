using Core, Pixel

public struct PaintContext
{
    painter:        #nonull *Painter = undefined
    renderer:       #nonull *RenderOgl = undefined
    isDisabled:     bool
}
