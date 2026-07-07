#global namespace InlineGeo

// Provider for cross_ast_struct_type.swg (in a separate file => separate Ast).
// corner() is a non-generic #[Inline] method whose body builds a struct literal of a type named
// UNQUALIFIED within this namespace. Mirrors core Math.Rectangle.topLeft() returning Point{.x,.y}.

struct GeoPoint
{
    x, y: s32
}

struct GeoMaker
{
    base: s32
}

impl GeoMaker
{
    #[Swag.Inline]
    mtd corner()->GeoPoint
    {
        return GeoPoint{.base, .base + 1}
    }
}
