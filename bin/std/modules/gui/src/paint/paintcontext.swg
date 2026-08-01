using Core, Pixel

// Supplies the painter, renderer, and inherited disabled state for one paint event.
public struct PaintContext
{
    painter:    *Painter   = undefined     // Painter receiving draw commands.
    renderer:   *RenderOgl = undefined     // Renderer that will execute the commands.
    isDisabled: bool                       // Whether an ancestor disables the painted window.
}
