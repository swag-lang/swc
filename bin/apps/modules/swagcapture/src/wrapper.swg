// Single source of truth mapping a form type to its edit mode and to the tool
// contexts it can serve as a model for. Every mode<->type<->model lookup below
// derives from this table; MainWnd.mdlByType is built in the same order.
struct FormDesc
{
    type:         typeinfo
    mode:         EditMode
    canHighlight: bool
    canPixSel:    bool
}

const FormRegistry: [?] FormDesc = [
    {FormShape,   EditMode.Shape,   true,  true},
    {FormArrow,   EditMode.Arrow,   false, false},
    {FormLine,    EditMode.Line,    true,  false},
    {FormPolygon, EditMode.Polygon, true,  true},
    {FormText,    EditMode.Text,    false, false},
    {FormDraw,    EditMode.Draw,    true,  true},
    {FormStep,    EditMode.Step,    false, false},
    {FormImage,   EditMode.Image,   false, false},
    {FormCallout, EditMode.Callout, false, false}]

func formDescIndex(type: typeinfo)->u64
{
    for i in FormRegistry.count
    {
        if FormRegistry[i].type == type do
            return i
    }

    unreachable
}

func formDescIndexOfMode(mode: EditMode)->u64
{
    for i in FormRegistry.count
    {
        if FormRegistry[i].mode == mode do
            return i
    }

    unreachable
}

impl MainWnd
{
    mtd updateModelValues(f: IForm)
    {
        switch
        {
        case let b = cast #try (*FormStep) f:
            .mdlFormStep    = b[]
            .mdlFormStep.ws = b.w
            .mdlFormStep.hs = b.h
        }
    }

    // The model of a given form type: an interface over the corresponding
    // 'mdlFormX' field, registered lazily so any way of constructing a MainWnd
    // (including the test fixtures) gets a valid mapping
    mtd modelFor(type: typeinfo)->IForm
    {
        if .mdlByType.isEmpty()
        {
            // FormRegistry order
            .mdlByType.add(.mdlFormShape)
            .mdlByType.add(.mdlFormArrow)
            .mdlByType.add(.mdlFormLine)
            .mdlByType.add(.mdlFormPolygon)
            .mdlByType.add(.mdlFormText)
            .mdlByType.add(.mdlFormDraw)
            .mdlByType.add(.mdlFormStep)
            .mdlByType.add(.mdlFormImage)
            .mdlByType.add(.mdlFormCallout)
        }

        return .mdlByType[formDescIndex(type)]
    }

    // Copy the full form into its model field: the model is the style+content
    // template used to create the next form of that type
    mtd copyFormToModel(f: IForm)
    {
        switch #complete
        {
        case let b = cast #try (*FormShape) f:
            .mdlFormShape = b[]

        case let b = cast #try (*FormImage) f:
            .mdlFormImage = b[]

        case let b = cast #try (*FormStep) f:
            .mdlFormStep    = b[]
            .mdlFormStep.ws = b.w
            .mdlFormStep.hs = b.h

        case let b = cast #try (*FormArrow) f:
            .mdlFormArrow = b[]

        case let b = cast #try (*FormLine) f:
            .mdlFormLine = b[]

        case let b = cast #try (*FormPolygon) f:
            .mdlFormPolygon = b[]

        case let b = cast #try (*FormText) f:
            .mdlFormText = b[]

            // The model is the style the next text form starts from, not the geometry of this
            // one: the glyph outlines belong to the text they were built for, and the next form
            // builds its own. Kept, they make selecting a text form copy every contour of it.
            .mdlFormText.paths.clear()
            .mdlFormText.borderPaths.clear()
            .mdlFormText.isDirty = true

        case let b = cast #try (*FormDraw) f:
            .mdlFormDraw = b[]

        case let b = cast #try (*FormCallout) f:
            .mdlFormCallout = b[]
        }
    }

    mtd updateModel(f: IForm)
    {
        let form = cast #assume (*BaseForm) f

        if form.subKind == .Highlight do
            .mdlHighlight = f
        elif form.subKind == .PixSel do
            .mdlPixSel = f

        .copyFormToModel(f)

        let desc = FormRegistry[formDescIndex(Swag.kindOf(f))]
        let mdl  = .modelFor(Swag.kindOf(f))
        .mdlFavorite = mdl
        if desc.canHighlight do
            .mdlHighlight = mdl
        if desc.canPixSel do
            .mdlPixSel = mdl
    }

    mtd updateEditMode(f: IForm)
    {
        if .editMode == .Favorites
        {
            .mdlFavorite = .modelFor(Swag.kindOf(f))
            return
        }

        let form = cast #assume (*BaseForm) f
        if form.subKind == .Highlight
        {
            .editMode = .Highlight
            return
        }
        elif form.subKind == .PixSel
        {
            .editMode = .PixSel
            return
        }

        .editMode = formToEditMode(f)
    }

    func formToEditMode(f: IForm)->EditMode
    {
        return FormRegistry[formDescIndex(Swag.kindOf(f))].mode
    }

    mtd editModeToModel(mode: EditMode)->IForm
    {
        switch mode
        {
        case .Favorites, .Selection: return .mdlFavorite
        case .Highlight: return .mdlHighlight
        case .PixSel:    return .mdlPixSel
        }

        return .modelFor(FormRegistry[formDescIndexOfMode(mode)].type)
    }

    mtd newFormFromModel(mode: EditMode, clear = false)->IForm
    {
        // Clone the model of the given mode, whatever its concrete type
        let mdlItf  = .editModeToModel(mode)
        let mdlType = Swag.kindOf(mdlItf)
        let storage = Memory.new(mdlType)!
        let result  = Swag.makeInterface(storage, mdlType, IForm)!
        let mdl     = cast #assume (*BaseForm) result
        mdlItf.copy(mdl, cast #assume (*BaseForm) mdlItf)

        // A new form starts without the model content, just its style
        if clear
        {
            switch mdlType
            {
            case FormImage:
                let f = cast #assume (*FormImage) mdl
                f.image.release()

            case FormPolygon:
                let f = cast #assume (*FormPolygon) mdl
                f.points.clear()

            case FormDraw:
                let f = cast #assume (*FormDraw) mdl
                f.points.clear()

            case FormCallout:
                let f = cast #assume (*FormCallout) mdl
                f.text.clear()
            }
        }

        return result
    }

    func newFormFromForm(it: IForm)->*BaseForm
    {
        let type     = Swag.kindOf(it)
        let storage  = Memory.new(type)!
        let view     = Swag.makeInterface(storage, type, IForm)!
        let mdlValue = cast #assume (*BaseForm) view
        it.copy(mdlValue, cast #assume (*BaseForm) it)
        return mdlValue
    }
}
