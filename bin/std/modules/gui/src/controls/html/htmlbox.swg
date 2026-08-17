#global internal

using Core, Pixel

// What a laid-out box is.
//
// An inline element never becomes a box: it becomes a run of items inside the block that
// contains it, which is what lets one paragraph mixing several spans stay one line-broken
// object instead of a tree of nested fragments.
#[Swag.NoDoc]
public enum HtmlBoxKind
{
    Block
    Flex
    Grid
    Table
    TableRow
    TableCell
    Replaced
}

// What one entry of an inline formatting context carries.
#[Swag.NoDoc]
public enum HtmlInlineKind
{
    Text
    Space
    Break
    Atomic
    OpenInline
    CloseInline
}

// One entry of an inline formatting context, before and after line breaking.
#[Swag.NoDoc]
public struct HtmlInlineItem
{
    kind:        HtmlInlineKind
    style:       u32
    node:        u32 = HtmlNoNode
    box:         u32 = HtmlNoNode
    text:        String
    sourceStart: u64
    sourceEnd:   u64
    width:       f32
    ascent:      f32
    descent:     f32
    x:           f32
    y:           f32
    visible:     bool
}

// One laid-out line of an inline formatting context.
#[Swag.NoDoc]
public struct HtmlLineBox
{
    top:      f32
    height:   f32
    baseline: f32
    left:     f32
    width:    f32
    first:    u32
    last:     u32
}

// What a box draws in the margin reserved beside its content.
#[Swag.NoDoc]
public enum HtmlMarkerKind
{
    None
    Text
    DisclosureClosed
    DisclosureOpen
    Checked
}

// One box of the layout tree.
//
// Rectangles are border boxes in document coordinates, so painting and hit testing never have to
// walk back up the tree to find out where a box really is.
#[Swag.NoDoc]
public struct HtmlBox
{
    node   = HtmlNoNode
    style:    u32
    kind:     HtmlBoxKind
    parent = HtmlNoNode
    children: Array'u32
    items:    Array'HtmlInlineItem
    lines:    Array'HtmlLineBox

    rect:        Math.Rectangle
    content:     Math.Rectangle
    // Complete subtree extent used to prune painting without losing visible overflow.
    paintBounds: Math.Rectangle

    // A list item draws its own marker, which sits outside the content box.
    marker:      String
    markerKind:  HtmlMarkerKind
    markerWidth: f32

    // An independently scrolled region keeps the size its content really needs, and the offset
    // the reader has moved it to.
    scrollHeight: f32
    scrollTop:    f32
    scrollable:   bool

    // A sticky box is placed in normal flow and then held against the viewport edge while its
    // container is still on screen.
    sticky:    bool
    stickyTop: f32

    // Intrinsic sizes are measured once, because a table column and a shrink-to-fit box both
    // need them and both are laid out more than once.
    minContent:   f32
    maxContent:   f32
    hasIntrinsic: bool
}

impl HtmlBox
{
    mtd const isTableStructure()->bool => .kind == .Table or .kind == .TableRow or .kind == .TableCell

    // Reports whether the box lays its children out as lines of text rather than as blocks.
    mtd const hasInlineContent()->bool => .items.count != 0
}
