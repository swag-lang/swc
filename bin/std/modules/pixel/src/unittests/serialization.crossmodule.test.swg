#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

// Regression test for cross-module attribute identity.
//
// 'Math.Vector2' is declared in 'core' with '#[Serialization.Final]'. When another module
// (here 'pixel') imports it, the importer regenerates the type's runtime typeinfo locally.
// A compiler bug used to tag imported *attribute* typeinfo with the importing module's
// namespace (e.g. 'Pixel.Core.Serialization.Final' instead of 'Core.Serialization.Final'),
// so 'Reflection.hasAttribute()' - which matches attributes by fullname - failed across the
// module boundary. That made 'isPodFinal()' return false for raw POD types like Vector2,
// which in turn broke raw array (de)serialization (TagBin read element-by-element over raw
// bytes and misaligned the whole stream).
#test
{
    @assert(Reflection.hasAttribute(#typeof(Math.Vector2), Serialization.Final))

        let (raw, sizeof) = Serialization.isPodFinal(#typeof(Math.Vector2))
    @assert(raw)
    @assert(sizeof == #sizeof(Math.Vector2))
}
