#global internal

using Core, Pixel

// The box an element generates.
#[Swag.NoDoc]
public enum HtmlDisplay
{
    None
    Contents
    Block
    Inline
    InlineBlock
    ListItem
    Flex
    InlineFlex
    Grid
    InlineGrid
    Table
    TableCaption
    TableRowGroup
    TableRow
    TableCell
    TableColumnGroup
}

// How a box is placed relative to normal flow.
#[Swag.NoDoc]
public enum HtmlPosition
{
    Static
    Relative
    Absolute
    Fixed
    Sticky
}

// How a box treats the white space of its text.
#[Swag.NoDoc]
public enum HtmlWhiteSpace
{
    Normal
    NoWrap
    Pre
    PreWrap
    PreLine
}

#[Swag.NoDoc]
public enum HtmlTextAlign
{
    Start
    Left
    Right
    Center
    Justify
}

#[Swag.NoDoc]
public enum HtmlTextTransform
{
    None
    Uppercase
    Lowercase
    Capitalize
}

// Where a run may break inside a word.
#[Swag.NoDoc]
public enum HtmlWordBreak
{
    Normal
    BreakAll
    KeepAll
}

#[Swag.NoDoc]
public enum HtmlOverflow
{
    Visible
    Hidden
    Scroll
    Auto
}

#[Swag.NoDoc]
public enum HtmlBorderStyle
{
    None
    Solid
    Dashed
    Dotted
    Double
}

#[Swag.NoDoc]
public enum HtmlListStyleType
{
    None
    Disc
    Circle
    Square
    Decimal
    LowerAlpha
    UpperAlpha
    LowerRoman
    UpperRoman
}

#[Swag.NoDoc]
public enum HtmlFlexDirection
{
    Row
    RowReverse
    Column
    ColumnReverse
}

#[Swag.NoDoc]
public enum HtmlFlexWrap
{
    NoWrap
    Wrap
    WrapReverse
}

// Distribution along the main axis, and along the cross axis for `align-content`.
#[Swag.NoDoc]
public enum HtmlJustify
{
    Start
    End
    Center
    SpaceBetween
    SpaceAround
    SpaceEvenly
}

// Alignment along the cross axis.
#[Swag.NoDoc]
public enum HtmlAlign
{
    Stretch
    Start
    End
    Center
    Baseline
}

#[Swag.NoDoc]
public enum HtmlBoxSizing
{
    ContentBox
    BorderBox
}

#[Swag.NoDoc]
public enum HtmlVerticalAlign
{
    Baseline
    Top
    Middle
    Bottom
    Sub
    Super
    TextTop
    TextBottom
}

// Which of the three faces a font stack asks for.
//
// A document names families the host does not carry, so the stack is reduced to the choice a
// themed application can actually honour.
#[Swag.NoDoc]
public enum HtmlFontFamilyKind
{
    Sans
    Serif
    Mono
}

#[Swag.EnumFlags, Swag.NoDoc]
public enum HtmlTextDecoration
{
    None = 0
    Underline
    Overline
    LineThrough
}

#[Swag.NoDoc]
public enum HtmlTextDecorationStyle
{
    Solid
    Dotted
}

// The four sides of a box, in CSS order.
#[Swag.NoDoc]
public struct HtmlEdges
{
    top:    HtmlLength
    right:  HtmlLength
    bottom: HtmlLength
    left:   HtmlLength
}

// One border side, whose width is already in pixels because no border unit is relative to
// anything layout discovers.
#[Swag.NoDoc]
public struct HtmlBorderEdge
{
    width:    f32
    style:    HtmlBorderStyle
    color:    Color
    hasColor: bool
}

// The colors an element inherits from the host when the document names none.
#[Swag.NoDoc]
public struct HtmlStyleDefaults
{
    text:           Color
    faintText:      Color
    background:     Color
    codeBackground: Color
    link:           Color
    hotLink:        Color
    border:         Color
    selection:      Color
    fontSize:       f32 = 16
    monoFontSize:   f32 = 14
}

// Every property the engine resolves for one element.
//
// The value is flat and copyable: a child starts from its parent's, which is what inheritance
// means, and the cascade then overwrites what the document says.
#[Swag.NoDoc]
public struct HtmlComputedStyle
{
    display:    HtmlDisplay = .Inline
    position:   HtmlPosition
    boxSizing:  HtmlBoxSizing
    floatLeft:  bool
    floatRight: bool
    clearLeft:  bool
    clearRight: bool

    // Inherited.
    color:                   Color
    fontSize:                f32               = 16
    fontWeight:              u32               = 400
    italic:                  bool
    fontFamily:              HtmlFontFamilyKind
    lineHeight                                 = HtmlLength.auto()
    letterSpacing:           f32
    wordSpacing:             f32
    textAlign:               HtmlTextAlign
    textTransform:           HtmlTextTransform
    textIndent:              HtmlLength
    whiteSpace:              HtmlWhiteSpace
    overflowWrap:            bool
    wordBreak:               HtmlWordBreak
    listStyleType:           HtmlListStyleType = .Disc
    listStyleInside:         bool
    visible                                    = true
    cursorPointer:           bool
    textDecoration                             = HtmlTextDecoration.None
    textDecorationColor:     Color
    hasDecorationColor:      bool
    textDecorationStyle:     HtmlTextDecorationStyle
    textDecorationThickness: f32
    textUnderlineOffset:     f32

    // Not inherited.
    background:           Color
    margin:               HtmlEdges
    padding:              HtmlEdges
    borderTop:            HtmlBorderEdge
    borderRight:          HtmlBorderEdge
    borderBottom:         HtmlBorderEdge
    borderLeft:           HtmlBorderEdge
    radiusTopLeft:        f32
    radiusTopRight:       f32
    radiusBottomRight:    f32
    radiusBottomLeft:     f32
    width                     = HtmlLength.auto()
    height                    = HtmlLength.auto()
    minWidth                  = HtmlLength.auto()
    maxWidth                  = HtmlLength.auto()
    minHeight                 = HtmlLength.auto()
    maxHeight                 = HtmlLength.auto()
    scrollMarginTop:      HtmlLength
    inset                     = HtmlEdges.auto()
    overflowX:            HtmlOverflow
    overflowY:            HtmlOverflow
    textOverflowEllipsis: bool
    opacity:              f32 = 1
    zIndex:               s32
    verticalAlign:        HtmlVerticalAlign

    flexDirection:  HtmlFlexDirection
    flexWrap:       HtmlFlexWrap
    justifyContent: HtmlJustify
    alignItems          = HtmlAlign.Stretch
    alignSelf           = HtmlAlign.Stretch
    hasAlignSelf:   bool
    alignContent        = HtmlJustify.Start
    rowGap:         HtmlLength
    columnGap:      HtmlLength
    flexGrow:       f32
    flexShrink:     f32 = 1
    flexBasis           = HtmlLength.auto()
    order:          s32

    // Grid tracks live in the value pool, because their count varies.
    gridColumnFirst: u32
    gridColumnCount: u32
    gridColumn:      s32
    gridRow:         s32

    // Generated content, for the boxes a pseudo-element selector creates.
    content:    u32 = HtmlNoNode
    hasContent: bool

    // Masks remain an unsupported image operation. A polygonal clip path is kept separately so
    // the painter can cut ordinary fills and outlines instead of dropping the decorated box.
    masked:   bool
    clipPath: u32 = HtmlNoNode
}

impl HtmlEdges
{
    mtd setAll(length: HtmlLength)
    {
        .top    = length
        .right  = length
        .bottom = length
        .left   = length
    }

    // The four automatic offsets a statically placed box carries, which is what `inset` means
    // before a document says anything.
    #[ConstExpr]
    public func auto()->HtmlEdges => {HtmlLength.auto(), HtmlLength.auto(), HtmlLength.auto(), HtmlLength.auto()}
}

impl HtmlComputedStyle
{
    // Builds the style the root inherits from, which is what the host theme decides.
    func fromDefaults(defaults: HtmlStyleDefaults)->HtmlComputedStyle
    {
        var result: retval
        result.color    = defaults.text
        result.fontSize = defaults.fontSize
        result.display  = .Block
        return result
    }

    // Copies the properties a child receives without asking for them.
    func inherited(parent: HtmlComputedStyle)->HtmlComputedStyle
    {
        var result: retval
        result.color                   = parent.color
        result.fontSize                = parent.fontSize
        result.fontWeight              = parent.fontWeight
        result.italic                  = parent.italic
        result.fontFamily              = parent.fontFamily
        result.lineHeight              = parent.lineHeight
        result.letterSpacing           = parent.letterSpacing
        result.wordSpacing             = parent.wordSpacing
        result.textAlign               = parent.textAlign
        result.textTransform           = parent.textTransform
        result.textIndent              = parent.textIndent
        result.whiteSpace              = parent.whiteSpace
        result.overflowWrap            = parent.overflowWrap
        result.wordBreak               = parent.wordBreak
        result.listStyleType           = parent.listStyleType
        result.listStyleInside         = parent.listStyleInside
        result.visible                 = parent.visible
        result.cursorPointer           = parent.cursorPointer
        result.textDecoration          = parent.textDecoration
        result.textDecorationColor     = parent.textDecorationColor
        result.hasDecorationColor      = parent.hasDecorationColor
        result.textDecorationStyle     = parent.textDecorationStyle
        result.textDecorationThickness = parent.textDecorationThickness
        result.textUnderlineOffset     = parent.textUnderlineOffset
        return result
    }

    // Reports whether the box takes part in an inline formatting context.
    mtd const isInlineLevel()->bool
    {
        switch .display
        {
        case .Inline, .InlineBlock, .InlineFlex, .InlineGrid: return true
        }

        return false
    }

    // Reports whether the box lays its own children out, rather than contributing text to the
    // line boxes of the block that contains it.
    mtd const isBlockContainer()->bool
    {
        switch .display
        {
        case .Inline, .None, .Contents: return false
        }

        return true
    }

    mtd const isFlexContainer()->bool => .display == .Flex or .display == .InlineFlex

    mtd const isGridContainer()->bool => .display == .Grid or .display == .InlineGrid

    // Reports whether the box is taken out of the normal flow of its parent.
    mtd const isOutOfFlow()->bool => .position == .Absolute or .position == .Fixed

    mtd const borderWidthX()->f32 => .borderLeft.width + .borderRight.width

    mtd const borderWidthY()->f32 => .borderTop.width + .borderBottom.width

    // Returns the line height in pixels for the element's own font size.
    mtd const resolvedLineHeight(pool: const *HtmlValuePool, fontHeight: f32)->f32
    {
        switch .lineHeight.kind
        {
        case .Pixels:
            return .lineHeight.value

        // A unitless line height is stored as a percentage of the font size, which is how it
        // keeps meaning when a descendant changes its own size.
        case .Percent:
            return .lineHeight.value * .fontSize
        }

        discard pool
        return fontHeight
    }
}

// Every declaration this engine understands.
//
// A property name is resolved once, when its stylesheet is parsed, and every element that
// selects the declaration then switches on an integer. A document of twenty thousand elements
// otherwise spends its style pass comparing the same strings over and over.
#[Swag.NoDoc]
public enum HtmlProperty
{
    Unknown
    Custom
    Display
    Position
    Color
    Background
    BackgroundColor
    Opacity
    Mask
    MaskImage
    WebkitMask
    WebkitMaskImage
    ClipPath
    Visibility
    Font
    FontSize
    FontWeight
    FontStyle
    FontFamily
    LineHeight
    LetterSpacing
    WordSpacing
    OverflowWrap
    WordBreak
    LineBreak
    TextAlign
    TextTransform
    TextIndent
    TextDecoration
    TextDecorationLine
    TextDecorationColor
    TextDecorationStyle
    TextDecorationThickness
    TextUnderlineOffset
    TextOverflow
    WhiteSpace
    VerticalAlign
    ListStyleType
    ListStylePosition
    ListStyle
    Cursor
    BoxSizing
    Float
    Clear
    Margin
    MarginTop
    MarginRight
    MarginBottom
    MarginLeft
    Padding
    PaddingTop
    PaddingRight
    PaddingBottom
    PaddingLeft
    Border
    BorderTop
    BorderRight
    BorderBottom
    BorderLeft
    BorderWidth
    BorderTopWidth
    BorderRightWidth
    BorderBottomWidth
    BorderLeftWidth
    BorderStyle
    BorderColor
    BorderTopColor
    BorderRightColor
    BorderBottomColor
    BorderLeftColor
    BorderRadius
    BorderTopLeftRadius
    BorderTopRightRadius
    BorderBottomRightRadius
    BorderBottomLeftRadius
    Width
    Height
    MinWidth
    MaxWidth
    MinHeight
    MaxHeight
    ScrollMarginTop
    Top
    Right
    Bottom
    Left
    Inset
    ZIndex
    Order
    Overflow
    OverflowX
    OverflowY
    FlexDirection
    FlexWrap
    FlexFlow
    JustifyContent
    AlignContent
    AlignItems
    AlignSelf
    Flex
    FlexGrow
    FlexShrink
    FlexBasis
    Gap
    GridGap
    RowGap
    GridRowGap
    ColumnGap
    GridColumnGap
    GridTemplateColumns
    GridColumn
    GridColumnStart
    GridRow
    GridRowStart
    Content
}

// Resolves a declaration name to the property it sets.
func htmlPropertyFromName(name: string)->HtmlProperty
{
    switch name
    {
    case "display":                    return .Display
    case "position":                   return .Position
    case "color":                      return .Color
    case "background":                 return .Background
    case "background-color":           return .BackgroundColor
    case "opacity":                    return .Opacity
    case "mask":                       return .Mask
    case "mask-image":                 return .MaskImage
    case "-webkit-mask":               return .WebkitMask
    case "-webkit-mask-image":         return .WebkitMaskImage
    case "clip-path":                  return .ClipPath
    case "visibility":                 return .Visibility
    case "font":                       return .Font
    case "font-size":                  return .FontSize
    case "font-weight":                return .FontWeight
    case "font-style":                 return .FontStyle
    case "font-family":                return .FontFamily
    case "line-height":                return .LineHeight
    case "letter-spacing":             return .LetterSpacing
    case "word-spacing":               return .WordSpacing
    case "overflow-wrap", "word-wrap": return .OverflowWrap
    case "word-break":                 return .WordBreak
    case "line-break":                 return .LineBreak
    case "text-align":                 return .TextAlign
    case "text-transform":             return .TextTransform
    case "text-indent":                return .TextIndent
    case "text-decoration":            return .TextDecoration
    case "text-decoration-line":       return .TextDecorationLine
    case "text-decoration-color":      return .TextDecorationColor
    case "text-decoration-style":      return .TextDecorationStyle
    case "text-decoration-thickness":  return .TextDecorationThickness
    case "text-underline-offset":      return .TextUnderlineOffset
    case "text-overflow":              return .TextOverflow
    case "white-space":                return .WhiteSpace
    case "vertical-align":             return .VerticalAlign
    case "list-style-type":            return .ListStyleType
    case "list-style-position":        return .ListStylePosition
    case "list-style":                 return .ListStyle
    case "cursor":                     return .Cursor
    case "box-sizing":                 return .BoxSizing
    case "float":                      return .Float
    case "clear":                      return .Clear
    case "margin":                     return .Margin
    case "margin-top":                 return .MarginTop
    case "margin-right":               return .MarginRight
    case "margin-bottom":              return .MarginBottom
    case "margin-left":                return .MarginLeft
    case "padding":                    return .Padding
    case "padding-top":                return .PaddingTop
    case "padding-right":              return .PaddingRight
    case "padding-bottom":             return .PaddingBottom
    case "padding-left":               return .PaddingLeft
    case "border":                     return .Border
    case "border-top":                 return .BorderTop
    case "border-right":               return .BorderRight
    case "border-bottom":              return .BorderBottom
    case "border-left":                return .BorderLeft
    case "border-width":               return .BorderWidth
    case "border-top-width":           return .BorderTopWidth
    case "border-right-width":         return .BorderRightWidth
    case "border-bottom-width":        return .BorderBottomWidth
    case "border-left-width":          return .BorderLeftWidth
    case "border-style":               return .BorderStyle
    case "border-color":               return .BorderColor
    case "border-top-color":           return .BorderTopColor
    case "border-right-color":         return .BorderRightColor
    case "border-bottom-color":        return .BorderBottomColor
    case "border-left-color":          return .BorderLeftColor
    case "border-radius":              return .BorderRadius
    case "border-top-left-radius":     return .BorderTopLeftRadius
    case "border-top-right-radius":    return .BorderTopRightRadius
    case "border-bottom-right-radius": return .BorderBottomRightRadius
    case "border-bottom-left-radius":  return .BorderBottomLeftRadius
    case "width":                      return .Width
    case "height":                     return .Height
    case "min-width":                  return .MinWidth
    case "max-width":                  return .MaxWidth
    case "min-height":                 return .MinHeight
    case "max-height":                 return .MaxHeight
    case "scroll-margin-top":          return .ScrollMarginTop
    case "top":                        return .Top
    case "right":                      return .Right
    case "bottom":                     return .Bottom
    case "left":                       return .Left
    case "inset":                      return .Inset
    case "z-index":                    return .ZIndex
    case "order":                      return .Order
    case "overflow":                   return .Overflow
    case "overflow-x":                 return .OverflowX
    case "overflow-y":                 return .OverflowY
    case "flex-direction":             return .FlexDirection
    case "flex-wrap":                  return .FlexWrap
    case "flex-flow":                  return .FlexFlow
    case "justify-content":            return .JustifyContent
    case "align-content":              return .AlignContent
    case "align-items":                return .AlignItems
    case "align-self":                 return .AlignSelf
    case "flex":                       return .Flex
    case "flex-grow":                  return .FlexGrow
    case "flex-shrink":                return .FlexShrink
    case "flex-basis":                 return .FlexBasis
    case "gap":                        return .Gap
    case "grid-gap":                   return .GridGap
    case "row-gap":                    return .RowGap
    case "grid-row-gap":               return .GridRowGap
    case "column-gap":                 return .ColumnGap
    case "grid-column-gap":            return .GridColumnGap
    case "grid-template-columns":      return .GridTemplateColumns
    case "grid-column":                return .GridColumn
    case "grid-column-start":          return .GridColumnStart
    case "grid-row":                   return .GridRow
    case "grid-row-start":             return .GridRowStart
    case "content":                    return .Content
    }

    return .Unknown
}

// What applying one declaration needs beyond the style it writes into.
#[Swag.NoDoc]
public struct HtmlDeclarationContext
{
    pool:     *HtmlValuePool = undefined
    length:   HtmlLengthContext
    defaults: HtmlStyleDefaults
}

impl HtmlComputedStyle
{
    private mtd length(value: string, context: *HtmlDeclarationContext)->{ length: HtmlLength, matched: bool }
    {
        return htmlParseLength(context.pool, value, context.length)
    }

    // Applies a color declaration, resolving `currentColor` against the color already computed.
    private mtd readColor(value: string, target: *Color)->bool
    {
        let parsed = htmlParseColor(value)
        if !parsed.matched do
            return false
        target[] = parsed.current ? .color : parsed.color
        return true
    }

    // Reads the one, two, three, or four values of a box shorthand.
    private mtd edges(value: string, target: *HtmlEdges, context: *HtmlDeclarationContext)
    {
        let parts = htmlSplitValue(value)
        if parts.isEmpty() do
            return

        var values: [4] HtmlLength = undefined
        for index in Math.min(parts.count, 4)
        {
            let parsed = .length(parts[index].toString(), context)
            values[index] = parsed.matched ? parsed.length : HtmlLength.pixels(0)
        }

        target.top    = values[0]
        target.right  = parts.count > 1 ? values[1] : values[0]
        target.bottom = parts.count > 2 ? values[2] : values[0]
        target.left   = parts.count > 3 ? values[3] : target.right
    }

    private func borderStyle(value: string)->{ style: HtmlBorderStyle, matched: bool }
    {
        var result: retval
        result.matched = true
        switch value
        {
        case "none", "hidden": result.style = .None
        case "solid":          result.style = .Solid
        case "dashed":         result.style = .Dashed
        case "dotted":         result.style = .Dotted
        case "double":         result.style = .Double
        case "groove", "ridge", "inset", "outset": result.style = .Solid
        default:               result.matched = false
        }

        return result
    }

    // Applies a `border` shorthand to one side, in any order of its three components.
    private mtd borderShorthand(value: string, edge: *HtmlBorderEdge, context: *HtmlDeclarationContext)
    {
        edge.style = .Solid
        edge.width = 1

        var sawWidth: bool
        let parts = htmlSplitValue(value)
        for part in parts
        {
            let text  = part.toString()
            let style = HtmlComputedStyle.borderStyle(text)
            if style.matched
            {
                edge.style = style.style
                continue
            }

            let parsed = .length(text, context)
            if parsed.matched and parsed.length.kind == .Pixels and !sawWidth
            {
                edge.width = parsed.length.value
                sawWidth   = true
                continue
            }

            var color: Color
            if .readColor(text, &color)
            {
                edge.color    = color
                edge.hasColor = true
            }
        }

        if edge.style == .None do
            edge.width = 0
    }

    private mtd borderWidth(value: string, edge: *HtmlBorderEdge, context: *HtmlDeclarationContext)
    {
        let parsed = .length(value, context)
        if parsed.matched and parsed.length.kind == .Pixels do
            edge.width = parsed.length.value
    }

    // Applies the four corner radii of a `border-radius` shorthand, ignoring the elliptical form
    // behind a slash because the painter draws circular corners.
    private mtd borderRadius(value: string, context: *HtmlDeclarationContext)
    {
        let slash = Utf8.indexOf(value, '/'rune)
        let text  = slash == Swag.U64.Max ? value : value[0 until slash]
        let parts = htmlSplitValue(text)
        if parts.isEmpty() do
            return

        var corners: [4] f32 = undefined
        for index in Math.min(parts.count, 4)
        {
            let parsed = .length(parts[index].toString(), context)
            corners[index] = parsed.matched ? parsed.length.resolve(context.pool, context.length) : 0
        }

        .radiusTopLeft     = corners[0]
        .radiusTopRight    = parts.count > 1 ? corners[1] : corners[0]
        .radiusBottomRight = parts.count > 2 ? corners[2] : corners[0]
        .radiusBottomLeft  = parts.count > 3 ? corners[3] : .radiusTopRight
    }

    private func justify(value: string)->{ value: HtmlJustify, matched: bool }
    {
        var result: retval
        result.matched = true
        switch value
        {
        case "flex-start", "start", "left", "normal": result.value = .Start
        case "flex-end", "end", "right":              result.value = .End
        case "center":                                result.value = .Center
        case "space-between":                         result.value = .SpaceBetween
        case "space-around":                          result.value = .SpaceAround
        case "space-evenly":                          result.value = .SpaceEvenly
        default:                                      result.matched = false
        }

        return result
    }

    private func align(value: string)->{ value: HtmlAlign, matched: bool }
    {
        var result: retval
        result.matched = true
        switch value
        {
        case "stretch", "normal", "auto":                   result.value = .Stretch
        case "flex-start", "start", "self-start":           result.value = .Start
        case "flex-end", "end", "self-end":                 result.value = .End
        case "center":                                      result.value = .Center
        case "baseline", "first baseline", "last baseline": result.value = .Baseline
        default:                                            result.matched = false
        }

        return result
    }

    // Reads a font stack and keeps the first family the host can honour.
    private func resolveFontFamily(value: string)->{ kind: HtmlFontFamilyKind, matched: bool }
    {
        var result: retval
        let families = htmlSplitValue(value, ','u8)
        for family in families
        {
            var name = family.toString()
            if @countof(name) >= 2 and (name[0] == '"' or name[0] == '\'') do
                name = name[1 until @countof(name) - 1]

            switch name
            {
            case "monospace", "ui-monospace", "consolas", "menlo", "courier", "courier new",
                 "cascadia mono", "cascadia code", "sfmono-regular", "dejavu sans mono", "liberation mono":
                result.kind    = .Mono
                result.matched = true
                return result

            case "serif", "ui-serif", "georgia", "times", "times new roman", "cambria", "garamond":
                result.kind    = .Serif
                result.matched = true
                return result

            case "sans-serif", "ui-sans-serif", "system-ui", "-apple-system", "segoe ui", "roboto",
                 "arial", "helvetica", "helvetica neue", "inter", "noto sans":
                result.kind    = .Sans
                result.matched = true
                return result
            }
        }

        return result
    }

    // Applies the `font` shorthand: `[style weight] size[/line-height] family-list`. A system
    // keyword (`caption`, `menu`, ...) names a host font and leaves the style untouched, and a
    // text without a recognizable size is not this grammar at all.
    private mtd fontShorthand(value: string, context: *HtmlDeclarationContext)
    {
        let parts = htmlSplitValue(value)

        // The size is the first part that reads as a length, a size keyword, or a size with an
        // attached `/line-height`. A bare number is a weight: a font size always carries a unit.
        var sizeIndex = Swag.U64.Max
        for index in parts.count
        {
            let text   = parts[index].toString()
            let number = htmlParseNumber(text)
            if number.eat == @countof(text) do
                continue

            let parsed = .length(text, context)
            var isSize = parsed.matched and !parsed.length.isAuto() and !parsed.length.isNone()
            if !isSize and Utf8.indexOf(text, '/'rune) != Swag.U64.Max do
                isSize = true
            if !isSize
            {
                switch text
                {
                case "xx-small", "x-small", "small", "medium", "large", "x-large", "xx-large", "smaller", "larger": isSize = true
                }
            }

            if !isSize do
                continue
            sizeIndex = index
            break
        }

        if sizeIndex == Swag.U64.Max do
            return

        // The shorthand resets every longhand it can set before its parts write over them.
        .italic     = false
        .fontWeight = 400
        .lineHeight = HtmlLength.auto()

        for index in sizeIndex
        {
            let text = parts[index].toString()
            switch text
            {
            case "italic", "oblique":
                .italic = true

            case "bold", "bolder":
                .fontWeight = 700

            case "lighter":
                .fontWeight = 300

            default:
                let number = htmlParseNumber(text)
                if number.eat == @countof(text) and number.value >= 1 and number.value <= 1000 do
                    .fontWeight = cast(u32) number.value
            }
        }

        let sizeText    = parts[sizeIndex].toString()
        var familyStart = sizeIndex + 1
        let slash       = Utf8.indexOf(sizeText, '/'rune)
        if slash != Swag.U64.Max
        {
            .applyDeclaration(.FontSize, Latin1.trim(sizeText[0 until slash]), context)
            .applyDeclaration(.LineHeight, Latin1.trim(sizeText[slash + 1 to]), context)
        }
        else
        {
            .applyDeclaration(.FontSize, sizeText, context)
            if familyStart + 1 < parts.count and parts[familyStart].toString() == "/"
            {
                .applyDeclaration(.LineHeight, parts[familyStart + 1].toString(), context)
                familyStart += 2
            }
        }

        if familyStart >= parts.count do
            return

        var family: String
        for index in familyStart until parts.count
        {
            if !family.isEmpty() do
                family += " "
            family += parts[index]
        }

        .applyDeclaration(.FontFamily, family.toString(), context)
    }

    private mtd flexShorthand(value: string, context: *HtmlDeclarationContext)
    {
        if value == "none"
        {
            .flexGrow   = 0
            .flexShrink = 0
            .flexBasis  = HtmlLength.auto()
            return
        }

        if value == "auto"
        {
            .flexGrow   = 1
            .flexShrink = 1
            .flexBasis  = HtmlLength.auto()
            return
        }

        let parts = htmlSplitValue(value)
        if parts.isEmpty() do
            return

        // A single number is the grow factor, and the basis collapses to zero so the factors
        // share the whole line rather than what is left of it.
        .flexBasis = HtmlLength.pixels(0)
        var numbers = 0'u32
        for part in parts
        {
            let text   = part.toString()
            let number = htmlParseNumber(text)
            if number.eat == @countof(text) and numbers < 2
            {
                if !numbers do
                    .flexGrow = number.value
                else do
                    .flexShrink = number.value
                numbers += 1
                continue
            }

            let parsed = .length(text, context)
            if parsed.matched do
                .flexBasis = parsed.length
        }

        if numbers == 1 do
            .flexShrink = 1
    }

    // Reads the track list of a grid container into the value pool.
    private mtd gridTemplate(value: string, context: *HtmlDeclarationContext)
    {
        let parts = htmlSplitValue(value)
        .gridColumnFirst = cast(u32) context.pool.calc.count
        .gridColumnCount = 0
        if parts.isEmpty() do
            return

        // `repeat()` is unrolled here so the rest of the engine only ever sees plain tracks. An
        // `auto-fill` or `auto-fit` count depends on the width layout discovers, so it keeps the
        // single flexible track the unexpanded form already produces.
        var tracks: Array'String
        for part in parts
        {
            let call = htmlFunctionArguments(part.toString(), "repeat")
            if call.matched and call.arguments.count == 2
            {
                let countText = Latin1.trim(call.arguments[0].toString())
                let count     = htmlParseNumber(countText)
                if count.eat == @countof(countText) and count.value >= 1
                {
                    // A count large enough to hit this bound is hostile input, not a layout.
                    let times = cast(u32) Math.min(count.value, 1024)
                    let inner = htmlSplitValue(call.arguments[1].toString())
                    for times
                    {
                        for track in inner do
                            tracks.add(String.from(track.toString()))
                    }

                    continue
                }
            }

            tracks.add(String.from(part.toString()))
        }

        // The tracks are stored as `Value` nodes, where the fraction count rides in `percent`
        // because a flexible track is never a percentage of anything.
        for part in tracks
        {
            var text  = part.toString()
            let range = htmlFunctionArguments(text, "minmax")
            if range.matched and range.arguments.count == 2 do
                text = range.arguments[1].toString()

            var node: HtmlCalcNode
            let parsed = .length(text, context)
            if parsed.matched and parsed.length.kind == .Fraction do
                node.percent = parsed.length.value
            elif parsed.matched do
                node.pixels = parsed.length.resolve(context.pool, context.length)
            else do
                node.percent = 1

            discard context.pool.addCalc(node)
            .gridColumnCount += 1
        }
    }

    // Applies one declaration, which the cascade has already ordered and resolved.
    mtd applyDeclaration(property: HtmlProperty, value: string, context: *HtmlDeclarationContext)
    {
        switch property
        {
        case .Display:
            switch value
            {
            case "none":                               .display = .None
            case "contents":                           .display = .Contents
            case "block", "flow-root":                 .display = .Block
            case "inline":                             .display = .Inline
            case "inline-block":                       .display = .InlineBlock
            case "list-item":                          .display = .ListItem
            case "flex":                               .display = .Flex
            case "inline-flex":                        .display = .InlineFlex
            case "grid":                               .display = .Grid
            case "inline-grid":                        .display = .InlineGrid
            case "table":                              .display = .Table
            case "table-caption":                      .display = .TableCaption
            case "table-row-group", "table-header-group", "table-footer-group": .display = .TableRowGroup
            case "table-row":                          .display = .TableRow
            case "table-cell":                         .display = .TableCell
            case "table-column", "table-column-group": .display = .TableColumnGroup
            }

        case .Position:
            switch value
            {
            case "static":   .position = .Static
            case "relative": .position = .Relative
            case "absolute": .position = .Absolute
            case "fixed":    .position = .Fixed
            case "sticky":   .position = .Sticky
            }

        case .Color:
            discard .readColor(value, &.color)

        case .Background, .BackgroundColor:

            // Only the color of a background shorthand is honoured; an image or a gradient is
            // read as "no color of its own" so the box keeps what is behind it.
            let parts = htmlSplitValue(value)
            var parsedColor: Color
            var found:       bool
            for part in parts
            {
                if !.readColor(part.toString(), &parsedColor) do
                    continue
                found = true
                break
            }

            if found do
                .background = parsedColor
            elif value == "none" do
                .background = Color.fromArgb(0'u32)

        case .Opacity:
            let number = htmlParseNumber(value)
            if number.eat do
                .opacity = Math.clamp(number.value, 0, 1)

        case .Mask, .MaskImage, .WebkitMask, .WebkitMaskImage:
            .masked = value != "none"

        case .ClipPath:
            .clipPath = value == "none" ? HtmlNoNode : context.pool.addString(value)

        case .Visibility:
            .visible = value != "hidden" and value != "collapse"

        case .FontSize:
            let parsed = .length(value, context)
            if parsed.matched and parsed.length.kind != .Auto
            {
                .fontSize               = Math.max(parsed.length.resolve(context.pool, context.length, context.length.fontSize), 1)
                context.length.fontSize = .fontSize
            }
            else
            {
                switch value
                {
                case "xx-small": .fontSize = context.defaults.fontSize * 0.5625
                case "x-small":  .fontSize = context.defaults.fontSize * 0.625
                case "small":    .fontSize = context.defaults.fontSize * 0.8125
                case "medium":   .fontSize = context.defaults.fontSize
                case "large":    .fontSize = context.defaults.fontSize * 1.125
                case "x-large":  .fontSize = context.defaults.fontSize * 1.5
                case "xx-large": .fontSize = context.defaults.fontSize * 2
                case "smaller":  .fontSize = context.length.fontSize * 0.83
                case "larger":   .fontSize = context.length.fontSize * 1.2
                }

                context.length.fontSize = .fontSize
            }

        case .FontWeight:
            switch value
            {
            case "normal":
                .fontWeight = 400

            case "bold":
                .fontWeight = 700

            case "lighter":
                .fontWeight = 300

            case "bolder":
                .fontWeight = 700

            default:
                let number = htmlParseNumber(value)
                if number.eat do
                    .fontWeight = cast(u32) Math.clamp(number.value, 1, 1000)
            }

        case .FontStyle:
            .italic = value == "italic" or value == "oblique"

        case .FontFamily:
            let family = HtmlComputedStyle.resolveFontFamily(value)
            if family.matched do
                .fontFamily = family.kind

        case .LineHeight:
            if value == "normal"
            {
                .lineHeight = HtmlLength.auto()
            }
            else
            {
                let number = htmlParseNumber(value)
                if number.eat == @countof(Latin1.trim(value))
                {
                    .lineHeight = HtmlLength.percent(number.value)
                }
                else
                {
                    let parsed = .length(value, context)
                    if parsed.matched do
                        .lineHeight = parsed.length
                }
            }

        case .LetterSpacing:
            let parsed = .length(value, context)
            .letterSpacing = parsed.matched ? parsed.length.resolve(context.pool, context.length) : 0

        case .WordSpacing:
            let parsed = .length(value, context)
            .wordSpacing = parsed.matched ? parsed.length.resolve(context.pool, context.length) : 0

        case .OverflowWrap:
            .overflowWrap = value == "break-word" or value == "anywhere"

        case .WordBreak:
            switch value
            {
            case "normal":     .wordBreak = .Normal
            case "break-all":  .wordBreak = .BreakAll
            case "keep-all":   .wordBreak = .KeepAll
            case "break-word": .overflowWrap = true
            }

        case .LineBreak:

            // The strictness grades govern CJK punctuation rules this engine does not model;
            // only the value that changes where a line may break is acted on.
            if value == "anywhere" do
                .wordBreak = .BreakAll

        case .Font:
            .fontShorthand(value, context)

        case .TextAlign:
            switch value
            {
            case "left":    .textAlign = .Left
            case "right":   .textAlign = .Right
            case "center":  .textAlign = .Center
            case "justify": .textAlign = .Justify
            case "start":   .textAlign = .Start
            case "end":     .textAlign = .Right
            }

        case .TextTransform:
            switch value
            {
            case "none":       .textTransform = .None
            case "uppercase":  .textTransform = .Uppercase
            case "lowercase":  .textTransform = .Lowercase
            case "capitalize": .textTransform = .Capitalize
            }

        case .TextIndent:
            let parsed = .length(value, context)
            if parsed.matched do
                .textIndent = parsed.length

        case .TextDecoration, .TextDecorationLine:
            .textDecoration = .None
            let parts = htmlSplitValue(value)
            for part in parts
            {
                switch part.toString()
                {
                case "underline":    .textDecoration.add(.Underline)
                case "overline":     .textDecoration.add(.Overline)
                case "line-through": .textDecoration.add(.LineThrough)
                }
            }

            for part in parts
            {
                var color: Color
                if .readColor(part.toString(), &color)
                {
                    .textDecorationColor = color
                    .hasDecorationColor  = true
                }
            }

        case .TextDecorationColor:
            var color: Color
            if .readColor(value, &color)
            {
                .textDecorationColor = color
                .hasDecorationColor  = true
            }

        case .TextDecorationStyle:
            .textDecorationStyle = value == "dotted" ? .Dotted : .Solid

        case .TextDecorationThickness:
            let parsed = .length(value, context)
            if parsed.matched do
                .textDecorationThickness = Math.max(parsed.length.resolve(context.pool, context.length), 0)

        case .TextUnderlineOffset:
            let parsed = .length(value, context)
            if parsed.matched do
                .textUnderlineOffset = parsed.length.resolve(context.pool, context.length)

        case .TextOverflow:
            .textOverflowEllipsis = value == "ellipsis"

        case .WhiteSpace:
            switch value
            {
            case "normal":                   .whiteSpace = .Normal
            case "nowrap":                   .whiteSpace = .NoWrap
            case "pre":                      .whiteSpace = .Pre
            case "pre-wrap", "break-spaces": .whiteSpace = .PreWrap
            case "pre-line":                 .whiteSpace = .PreLine
            }

        case .VerticalAlign:
            switch value
            {
            case "baseline":    .verticalAlign = .Baseline
            case "top":         .verticalAlign = .Top
            case "middle":      .verticalAlign = .Middle
            case "bottom":      .verticalAlign = .Bottom
            case "sub":         .verticalAlign = .Sub
            case "super":       .verticalAlign = .Super
            case "text-top":    .verticalAlign = .TextTop
            case "text-bottom": .verticalAlign = .TextBottom
            }

        case .ListStyleType:
            switch value
            {
            case "none":                       .listStyleType = .None
            case "disc":                       .listStyleType = .Disc
            case "circle":                     .listStyleType = .Circle
            case "square":                     .listStyleType = .Square
            case "decimal":                    .listStyleType = .Decimal
            case "lower-alpha", "lower-latin": .listStyleType = .LowerAlpha
            case "upper-alpha", "upper-latin": .listStyleType = .UpperAlpha
            case "lower-roman":                .listStyleType = .LowerRoman
            case "upper-roman":                .listStyleType = .UpperRoman
            }

        case .ListStylePosition:
            .listStyleInside = value == "inside"

        case .ListStyle:
            let parts = htmlSplitValue(value)
            for part in parts
            {
                .applyDeclaration(.ListStyleType, part.toString(), context)
                .applyDeclaration(.ListStylePosition, part.toString(), context)
            }

        case .Cursor:
            .cursorPointer = value == "pointer"

        case .BoxSizing:
            .boxSizing = value == "border-box" ? .BorderBox : .ContentBox

        case .Float:
            .floatLeft  = value == "left"
            .floatRight = value == "right"

        case .Clear:
            .clearLeft  = value == "left" or value == "both"
            .clearRight = value == "right" or value == "both"

        case .Margin:
            .edges(value, &.margin, context)

        case .MarginTop:
            let parsed = .length(value, context)
            if parsed.matched do
                .margin.top = parsed.length

        case .MarginRight:
            let parsed = .length(value, context)
            if parsed.matched do
                .margin.right = parsed.length

        case .MarginBottom:
            let parsed = .length(value, context)
            if parsed.matched do
                .margin.bottom = parsed.length

        case .MarginLeft:
            let parsed = .length(value, context)
            if parsed.matched do
                .margin.left = parsed.length

        case .Padding:
            .edges(value, &.padding, context)

        case .PaddingTop:
            let parsed = .length(value, context)
            if parsed.matched do
                .padding.top = parsed.length

        case .PaddingRight:
            let parsed = .length(value, context)
            if parsed.matched do
                .padding.right = parsed.length

        case .PaddingBottom:
            let parsed = .length(value, context)
            if parsed.matched do
                .padding.bottom = parsed.length

        case .PaddingLeft:
            let parsed = .length(value, context)
            if parsed.matched do
                .padding.left = parsed.length

        case .Border:
            .borderShorthand(value, &.borderTop, context)
            .borderRight  = .borderTop
            .borderBottom = .borderTop
            .borderLeft   = .borderTop

        case .BorderTop:
            .borderShorthand(value, &.borderTop, context)

        case .BorderRight:
            .borderShorthand(value, &.borderRight, context)

        case .BorderBottom:
            .borderShorthand(value, &.borderBottom, context)

        case .BorderLeft:
            .borderShorthand(value, &.borderLeft, context)

        case .BorderWidth:
            .borderWidth(value, &.borderTop, context)
            .borderRight.width  = .borderTop.width
            .borderBottom.width = .borderTop.width
            .borderLeft.width   = .borderTop.width

        case .BorderTopWidth:
            .borderWidth(value, &.borderTop, context)

        case .BorderRightWidth:
            .borderWidth(value, &.borderRight, context)

        case .BorderBottomWidth:
            .borderWidth(value, &.borderBottom, context)

        case .BorderLeftWidth:
            .borderWidth(value, &.borderLeft, context)

        case .BorderStyle:
            let style = HtmlComputedStyle.borderStyle(value)
            if style.matched
            {
                .borderTop.style    = style.style
                .borderRight.style  = style.style
                .borderBottom.style = style.style
                .borderLeft.style   = style.style
            }

        case .BorderColor:
            var color: Color
            if .readColor(value, &color)
            {
                .borderTop.color       = color
                .borderRight.color     = color
                .borderBottom.color    = color
                .borderLeft.color      = color
                .borderTop.hasColor    = true
                .borderRight.hasColor  = true
                .borderBottom.hasColor = true
                .borderLeft.hasColor   = true
            }

        case .BorderTopColor:
            if .readColor(value, &.borderTop.color) do
                .borderTop.hasColor = true

        case .BorderRightColor:
            if .readColor(value, &.borderRight.color) do
                .borderRight.hasColor = true

        case .BorderBottomColor:
            if .readColor(value, &.borderBottom.color) do
                .borderBottom.hasColor = true

        case .BorderLeftColor:
            if .readColor(value, &.borderLeft.color) do
                .borderLeft.hasColor = true

        case .BorderRadius:
            .borderRadius(value, context)

        case .BorderTopLeftRadius:
            let parsed = .length(value, context)
            if parsed.matched do
                .radiusTopLeft = parsed.length.resolve(context.pool, context.length)

        case .BorderTopRightRadius:
            let parsed = .length(value, context)
            if parsed.matched do
                .radiusTopRight = parsed.length.resolve(context.pool, context.length)

        case .BorderBottomRightRadius:
            let parsed = .length(value, context)
            if parsed.matched do
                .radiusBottomRight = parsed.length.resolve(context.pool, context.length)

        case .BorderBottomLeftRadius:
            let parsed = .length(value, context)
            if parsed.matched do
                .radiusBottomLeft = parsed.length.resolve(context.pool, context.length)

        case .Width:
            let parsed = .length(value, context)
            if parsed.matched do
                .width = parsed.length

        case .Height:
            let parsed = .length(value, context)
            if parsed.matched do
                .height = parsed.length

        case .MinWidth:
            let parsed = .length(value, context)
            if parsed.matched do
                .minWidth = parsed.length

        case .MaxWidth:
            let parsed = .length(value, context)
            if parsed.matched do
                .maxWidth = parsed.length

        case .MinHeight:
            let parsed = .length(value, context)
            if parsed.matched do
                .minHeight = parsed.length

        case .MaxHeight:
            let parsed = .length(value, context)
            if parsed.matched do
                .maxHeight = parsed.length

        case .ScrollMarginTop:
            let parsed = .length(value, context)
            if parsed.matched do
                .scrollMarginTop = parsed.length

        case .Top:
            let parsed = .length(value, context)
            if parsed.matched do
                .inset.top = parsed.length

        case .Right:
            let parsed = .length(value, context)
            if parsed.matched do
                .inset.right = parsed.length

        case .Bottom:
            let parsed = .length(value, context)
            if parsed.matched do
                .inset.bottom = parsed.length

        case .Left:
            let parsed = .length(value, context)
            if parsed.matched do
                .inset.left = parsed.length

        case .Inset:
            .edges(value, &.inset, context)

        case .ZIndex:
            let number = htmlParseNumber(value)
            if number.eat do
                .zIndex = cast(s32) number.value

        case .Order:
            let number = htmlParseNumber(value)
            if number.eat do
                .order = cast(s32) number.value

        case .Overflow:
            .applyDeclaration(.OverflowX, value, context)
            .applyDeclaration(.OverflowY, value, context)

        case .OverflowX:
            switch value
            {
            case "visible":        .overflowX = .Visible
            case "hidden", "clip": .overflowX = .Hidden
            case "scroll":         .overflowX = .Scroll
            case "auto":           .overflowX = .Auto
            }

        case .OverflowY:
            switch value
            {
            case "visible":        .overflowY = .Visible
            case "hidden", "clip": .overflowY = .Hidden
            case "scroll":         .overflowY = .Scroll
            case "auto":           .overflowY = .Auto
            }

        case .FlexDirection:
            switch value
            {
            case "row":            .flexDirection = .Row
            case "row-reverse":    .flexDirection = .RowReverse
            case "column":         .flexDirection = .Column
            case "column-reverse": .flexDirection = .ColumnReverse
            }

        case .FlexWrap:
            switch value
            {
            case "nowrap":       .flexWrap = .NoWrap
            case "wrap":         .flexWrap = .Wrap
            case "wrap-reverse": .flexWrap = .WrapReverse
            }

        case .FlexFlow:
            let parts = htmlSplitValue(value)
            for part in parts
            {
                .applyDeclaration(.FlexDirection, part.toString(), context)
                .applyDeclaration(.FlexWrap, part.toString(), context)
            }

        case .JustifyContent:
            let parsed = HtmlComputedStyle.justify(value)
            if parsed.matched do
                .justifyContent = parsed.value

        case .AlignContent:
            let parsed = HtmlComputedStyle.justify(value)
            if parsed.matched do
                .alignContent = parsed.value

        case .AlignItems:
            let parsed = HtmlComputedStyle.align(value)
            if parsed.matched do
                .alignItems = parsed.value

        case .AlignSelf:
            let parsed = HtmlComputedStyle.align(value)
            if parsed.matched
            {
                .alignSelf    = parsed.value
                .hasAlignSelf = true
            }

        case .Flex:
            .flexShorthand(value, context)

        case .FlexGrow:
            let number = htmlParseNumber(value)
            if number.eat do
                .flexGrow = number.value

        case .FlexShrink:
            let number = htmlParseNumber(value)
            if number.eat do
                .flexShrink = number.value

        case .FlexBasis:
            let parsed = .length(value, context)
            if parsed.matched do
                .flexBasis = parsed.length

        case .Gap, .GridGap:
            let parts = htmlSplitValue(value)
            if parts.count
            {
                let row = .length(parts[0].toString(), context)
                if row.matched
                {
                    .rowGap    = row.length
                    .columnGap = row.length
                }

                if parts.count > 1
                {
                    let column = .length(parts[1].toString(), context)
                    if column.matched do
                        .columnGap = column.length
                }
            }

        case .RowGap, .GridRowGap:
            let parsed = .length(value, context)
            if parsed.matched do
                .rowGap = parsed.length

        case .ColumnGap, .GridColumnGap:
            let parsed = .length(value, context)
            if parsed.matched do
                .columnGap = parsed.length

        case .GridTemplateColumns:
            .gridTemplate(value, context)

        case .GridColumn, .GridColumnStart:
            let number = htmlParseNumber(value)
            if number.eat do
                .gridColumn = cast(s32) number.value

        case .GridRow, .GridRowStart:
            let number = htmlParseNumber(value)
            if number.eat do
                .gridRow = cast(s32) number.value

        case .Content:
            var text = Latin1.trim(value)
            if @countof(text) >= 2 and (text[0] == '"' or text[0] == '\'') and text[@countof(text) - 1] == text[0]
            {
                .content    = context.pool.addString(htmlDecodeText(text[1 until @countof(text) - 1]).toString())
                .hasContent = true
            }
            elif text == "none" or text == "normal"
            {
                .hasContent = false
            }
            else
            {
                // A counter, an attribute reference, or an image generates a box with no text of
                // its own, which is exactly what a decorative rule wants.
                .content    = context.pool.addString("")
                .hasContent = true
            }
        }
    }
}
