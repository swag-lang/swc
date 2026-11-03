#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// A new upload starts a fresh rectangle; empty glyphs never dirty a clean page.
#test
{
    var atlas: GlyphAtlas
    atlas.markDirty(2, 5, 3, 4)
    atlas.markDirty(9, 1, 2, 6)
    Swag.require(atlas.dirty)
    Swag.require(atlas.dirtyMinX == 2 and atlas.dirtyMinY == 1)
    Swag.require(atlas.dirtyMaxX == 11 and atlas.dirtyMaxY == 9)

    atlas.dirty = false
    atlas.markDirty(20, 30, 0, 4)
    atlas.markDirty(20, 30, 4, 0)
    Swag.require(not atlas.dirty)
    atlas.markDirty(20, 30, 4, 5)
    Swag.require(atlas.dirtyMinX == 20 and atlas.dirtyMinY == 30)
    Swag.require(atlas.dirtyMaxX == 24 and atlas.dirtyMaxY == 35)
}

// Reconstruct the atlas exactly as an incremental texture upload does. This checks row stride,
// the vertical storage flip, multi-channel offsets, and glyphs wrapping onto the next shelf.
private func testAtlasUpload(mode: FontRenderMode)
{
    var cache: FontCache
    let face = expect TypeFace.load(getTestDataPath("segoeui.ttf"))
    let font = cache.createFont(face, 24, mode)
    discard font.getGlyphDesc('A')
    let atlas = &font.cache.atlases[0]
    var uploaded: Array'u8
    uploaded.add(atlas.data.toSlice())
    atlas.dirty      = false
    font.cache.dirty = false

    discard font.getGlyphDesc('B')
    Swag.require(atlas.dirty and font.cache.dirty)
    let changedPixels = (atlas.dirtyMaxX - atlas.dirtyMinX) * (atlas.dirtyMaxY - atlas.dirtyMinY)
    Swag.require(changedPixels * 4 < atlas.width / atlas.bytesPerPixel * atlas.height)

    // Force the next glyph to start a shelf without filling the entire page with test text.
    atlas.curX = cast(s32, atlas.width)
    discard font.getGlyphDesc('g')
    Swag.require(font.cache.atlases.count == 1)
    let rowBytes = (atlas.dirtyMaxX - atlas.dirtyMinX) * atlas.bytesPerPixel
    for y in atlas.dirtyMinY until atlas.dirtyMaxY
    {
        let offset = cast(u64, y) * atlas.width + atlas.dirtyMinX * atlas.bytesPerPixel
        Memory.copy(uploaded.storage() + offset, atlas.data.storage() + offset, rowBytes)
    }

    for value, index in uploaded do
        Swag.require(value == atlas.data[index])

    atlas.dirty      = false
    font.cache.dirty = false
    discard font.getGlyphDesc('B')
    Swag.require(not atlas.dirty and not font.cache.dirty)
}

#test { testAtlasUpload(.Bitmap) }
#test { testAtlasUpload(.Msdf) }
