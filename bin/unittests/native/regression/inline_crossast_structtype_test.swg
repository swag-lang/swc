#global private

// This #test is NOT in the InlineGeo namespace, and lives in a different file (=> different Ast)
// than GeoMaker.corner. When corner() is inlined here, its body's `GeoPoint{...}` must keep the
// type resolved to InlineGeo.GeoPoint across the cross-Ast inline (it would otherwise re-resolve
// the bare name `GeoPoint` in this file's scope and fail with "unknown symbol 'GeoPoint'").

#test
{
    var m: InlineGeo.GeoMaker
    m.base = 41
    let c = m.corner()
    @assert(c.x == 41)
    @assert(c.y == 42)
}
