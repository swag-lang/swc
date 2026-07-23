// Single source of truth mapping a form type to its edit mode and to the tool
// contexts it can serve as a model for. Every mode<->type<->model lookup below
// derives from this table; MainWnd.mdlByType is built in the same order.
struct FormDesc
{
    type:         typeinfo = undefined
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
    for i in @countof(FormRegistry)
    {
        if FormRegistry[i].type == type do
            return i
    }

    unreachable
}

func formDescIndexOfMode(mode: EditMode)->u64
{
    for i in @countof(FormRegistry)
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
        switch f
        {
        case FormStep as b:
            .mdlFormStep    = dref b
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
            .mdlByType.add(cast(IForm) .mdlFormShape)
            .mdlByType.add(cast(IForm) .mdlFormArrow)
            .mdlByType.add(cast(IForm) .mdlFormLine)
            .mdlByType.add(cast(IForm) .mdlFormPolygon)
            .mdlByType.add(cast(IForm) .mdlFormText)
            .mdlByType.add(cast(IForm) .mdlFormDraw)
            .mdlByType.add(cast(IForm) .mdlFormStep)
            .mdlByType.add(cast(IForm) .mdlFormImage)
            .mdlByType.add(cast(IForm) .mdlFormCallout)
        }

        return .mdlByType[formDescIndex(type)]
    }

    // Copy the full form into its model field: the model is the style+content
    // template used to create the next form of that type
    mtd copyFormToModel(f: IForm)
    {
        #[Swag.Complete]
        switch f
        {
        case FormShape as b:
            .mdlFormShape = dref b
        case FormImage as b:
            .mdlFormImage = dref b
        case FormStep as b:
            .mdlFormStep    = dref b
            .mdlFormStep.ws = b.w
            .mdlFormStep.hs = b.h
        case FormArrow as b:
            .mdlFormArrow = dref b
        case FormLine as b:
            .mdlFormLine = dref b
        case FormPolygon as b:
            .mdlFormPolygon = dref b
        case FormText as b:
            .mdlFormText = dref b
        case FormDraw as b:
            .mdlFormDraw = dref b
        case FormCallout as b:
            .mdlFormCallout = dref b
        }
    }

    mtd updateModel(f: IForm)
    {
        let form = cast(*BaseForm) @dataof(f)

        if form.subKind == .Highlight do
            .mdlHighlight = f
        elif form.subKind == .PixSel do
            .mdlPixSel = f

        .copyFormToModel(f)

        let desc = FormRegistry[formDescIndex(@kindof(f))]
        let mdl  = .modelFor(@kindof(f))
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
            .mdlFavorite = .modelFor(@kindof(f))
            return
        }

        let form = cast(*BaseForm) @dataof(f)
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
        return FormRegistry[formDescIndex(@kindof(f))].mode
    }

    mtd editModeToModel(mode: EditMode)->IForm
    {
        switch mode
        {
        case Favorites, Selection:
            return notnull .mdlFavorite
        case Highlight:
            return notnull .mdlHighlight
        case PixSel:
            return notnull .mdlPixSel
        }

        return .modelFor(FormRegistry[formDescIndexOfMode(mode)].type)
    }

    mtd newFormFromModel(mode: EditMode, clear = false)->IForm
    {
        // Clone the model of the given mode, whatever its concrete type
        let mdlItf  = .editModeToModel(mode)
        let mdlType = @kindof(mdlItf)
        let mdl     = cast(*BaseForm) notnull Memory.new(mdlType)
        mdlItf.copy(mdl, cast(*BaseForm) @dataof(mdlItf))

        // A new form starts without the model content, just its style
        if clear
        {
            switch mdlType
            {
            case FormImage:
                let f = cast(*FormImage) mdl
                f.image.release()
            case FormPolygon:
                let f = cast(*FormPolygon) mdl
                f.points.clear()
            case FormDraw:
                let f = cast(*FormDraw) mdl
                f.points.clear()
            case FormCallout:
                let f = cast(*FormCallout) mdl
                f.text.clear()
            }
        }

        return @mkinterface(mdl, mdlType, IForm)
    }

    func newFormFromForm(it: IForm)->*BaseForm
    {
        let mdlValue = cast(*BaseForm) notnull Memory.new(@kindof(it))
        it.copy(mdlValue, cast(*BaseForm) @dataof(it))
        return mdlValue
    }
}
