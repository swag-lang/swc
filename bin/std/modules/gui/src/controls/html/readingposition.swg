#global public

using Core

// An owned logical text location in an unchanged HTML source.
//
// Capture with [[Gui.HtmlView.readingPosition]] and restore after changing typography or width
// with [[Gui.HtmlView.restoreReadingPosition]]. It contains no view or text pointers and may
// outlive the view. It is valid only for the same unchanged, decoded document source; it is not
// a persistent serialization format. A default value has no location.
#[Swag.Opaque]
struct HtmlReadingPosition
{
    internal
    {
        sourceOffset: u64
        textOffset:   u64
        lineFraction: f32
        hasValue:     bool
        atStart:      bool
    }
}

impl HtmlReadingPosition
{
    // Reports whether this value contains a captured text location.
    mtd const isValid()->bool => .hasValue
}

impl HtmlView
{
    private mtd const isRootReadingBox(index: u32)->bool
    {
        var current = index
        while current != HtmlNoNode
        {
            let box   = .layout.constBox(current)
            let style = .layout.constStyle(box.style)
            if box.scrollable or style.position == .Fixed or style.position == .Sticky do
                return false
            current = box.parent
        }

        return true
    }

    // Captures the first text line reaching below `line`, a document coordinate inside the view.
    private mtd const firstTextBelow(line: f32)->HtmlReadingPosition
    {
        var result: HtmlReadingPosition
        if .virtualSource do
            return result
        let bottom = .scroll.scrollPosition().y + .scroll.view.paddedClientRect().height
        var best   = Swag.F32.Inf
        var left   = Swag.F32.Inf
        for box, index in .layout.boxes
        {
            if not .isRootReadingBox(cast(u32, index)) do
                continue
            for item in box.items
            {
                if item.kind != .Text or
                   not item.visible or
                   item.node == HtmlNoNode or
                   item.sourceStart >= item.sourceEnd do
                    continue
                let node = .document.constNode(item.node)
                if node.kind != .Text or not .layout.constStyle(item.style).visible do
                    continue
                let height = Math.max(item.ascent + item.descent, 1)
                if item.y + height <= line or item.y >= bottom do
                    continue
                if item.y > best or (item.y == best and item.x >= left) do
                    continue
                best                = item.y
                left                = item.x
                result.sourceOffset = node.sourceOffset
                result.textOffset   = item.sourceStart
                result.lineFraction = Math.clamp((line - item.y) / height, 0, 1)
                result.hasValue     = true
                result.atStart      = line <= 0
            }
        }

        return result
    }

    // Captures the first visible text passage independently of its current pixel position.
    //
    // The result owns no resources. Empty/image-only documents and virtual source windows return
    // an invalid position. Fixed/sticky content and independent scroll regions are excluded.
    // Streaming documents can capture text that has already been laid out.
    // The document origin is retained exactly, including leading margins.
    mtd const readingPosition()->HtmlReadingPosition => .firstTextBelow(.scroll.scrollPosition().y)

    // Returns the source byte offset of the text being read, or `U64.Max` when there is none.
    //
    // It is the first text below the air a reveal keeps above its destination, so the heading
    // [[Gui.HtmlView.revealFileOffset]] or a fragment brought into view is the one being read:
    // the last one of [[Gui.HtmlView.headings]] at or before the offset. The offset addresses the
    // current source like a heading's. When no text reaches below that air, the first visible
    // text answers; the offset is unavailable wherever [[Gui.HtmlView.readingPosition]] is invalid.
    mtd const readingOffset()->u64
    {
        let top     = .scroll.scrollPosition().y
        var reading = .firstTextBelow(top + HtmlRevealClearance)
        if not reading.hasValue do
            reading = .firstTextBelow(top)
        return reading.hasValue ? reading.sourceOffset : Swag.U64.Max
    }

    // Returns the share of the document above the top of the view, from 0 at the top to 1 once
    // the end is on screen, as a reading progress shows it.
    //
    // A scroll position is a whole pixel while the extent is not, so a view scrolled as far as it
    // goes can stop half a pixel short of the extent: it is at the end all the same.
    mtd const readingProgress()->f32
    {
        let extent   = .scroll.scrollSize.y - .scroll.clientRect().height
        let position = .scroll.scrollPosition().y
        return extent > 0 and extent - position > 0.5 ? Math.clamp(position / extent, 0, 1) : 1
    }

    // Restores a captured text passage in the currently laid-out, unchanged HTML source.
    //
    // Returns false without scrolling when the position is invalid, its text is not laid out
    // yet, or the view uses a virtual source window. While streaming, retry after
    // [[Gui.HtmlView.sigDocumentChanged]]. A successful restore preserves the position within
    // the text line at the viewport top, subject to the document's scroll bounds. It does not
    // change selection, search, keyboard focus or independently scrolled elements.
    //
    // ```swag
    // let passage = view.readingPosition()
    // view.setDocumentStyle(style)
    // discard view.restoreReadingPosition(passage)
    // ```
    mtd restoreReadingPosition(position: HtmlReadingPosition)->bool
    {
        if not position.hasValue or .virtualSource do
            return false
        if position.atStart
        {
            .scroll.setScrollPos(.scroll.scrollPosition().x, 0)
            return true
        }

        var node = HtmlNoNode
        for index in .document.nodes.count
        {
            let candidate = .document.constNode(cast(u32, index))
            if candidate.kind == .Text and candidate.sourceOffset == position.sourceOffset
            {
                node = cast(u32, index)
                break
            }
        }

        if node == HtmlNoNode do
            return false
        for box, index in .layout.boxes
        {
            if not .isRootReadingBox(cast(u32, index)) do
                continue
            for item in box.items where item.kind == .Text and
                                        item.visible and
                                        item.node == node and
                                        item.sourceStart <= position.textOffset and
                                        item.sourceEnd > position.textOffset
            {
                if not .layout.constStyle(item.style).visible do
                    continue
                let height = Math.max(item.ascent + item.descent, 1)
                .scroll.setScrollPos(.scroll.scrollPosition().x, Math.max(item.y + height * position.lineFraction, 0))
                .canvas.invalidate()
                return true
            }
        }

        return false
    }
}
