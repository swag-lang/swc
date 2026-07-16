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

    mtd updateModel(f: IForm)
    {
        let form = cast(*BaseForm) @dataof(f)

        if form.subKind == .Highlight do
            .mdlHighlight = f
        elif form.subKind == .PixSel do
            .mdlPixSel = f

        #[Swag.Complete]
        switch f
        {
        case FormShape as b:
            .mdlFormShape = dref b
            .mdlFavorite  = &.mdlFormShape
            .mdlHighlight = &.mdlFormShape
            .mdlPixSel    = &.mdlFormShape
        case FormImage as b:
            .mdlFormImage = dref b
            .mdlFavorite  = &.mdlFormImage
        case FormStep as b:
            .mdlFormStep    = dref b
            .mdlFormStep.ws = b.w
            .mdlFormStep.hs = b.h
            .mdlFavorite    = &.mdlFormStep
        case FormArrow as b:
            .mdlFormArrow = dref b
            .mdlFavorite  = &.mdlFormArrow
        case FormLine as b:
            .mdlFormLine  = dref b
            .mdlFavorite  = &.mdlFormLine
            .mdlHighlight = &.mdlFormLine
        case FormPolygon as b:
            .mdlFormPolygon = dref b
            .mdlFavorite    = &.mdlFormPolygon
            .mdlHighlight   = &.mdlFormPolygon
            .mdlPixSel      = &.mdlFormPolygon
        case FormText as b:
            .mdlFormText = dref b
            .mdlFavorite = &.mdlFormText
        case FormDraw as b:
            .mdlFormDraw  = dref b
            .mdlFavorite  = &.mdlFormDraw
            .mdlHighlight = &.mdlFormDraw
            .mdlPixSel    = &.mdlFormDraw
        case FormCallout as b:
            .mdlFormCallout = dref b
            .mdlFavorite    = &.mdlFormCallout
        }
    }

    mtd updateEditMode(f: IForm)
    {
        if .editMode == .Favorites
        {
            #[Swag.Complete]
            switch f
            {
            case FormShape:
                .mdlFavorite = .mdlFormShape
            case FormImage:
                .mdlFavorite = .mdlFormImage
            case FormStep:
                .mdlFavorite = .mdlFormStep
            case FormArrow:
                .mdlFavorite = .mdlFormArrow
            case FormLine:
                .mdlFavorite = .mdlFormLine
            case FormPolygon:
                .mdlFavorite = .mdlFormPolygon
            case FormText:
                .mdlFavorite = .mdlFormText
            case FormDraw:
                .mdlFavorite = .mdlFormDraw
            case FormCallout:
                .mdlFavorite = .mdlFormCallout
            }

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

        #[Swag.Complete]
        switch f
        {
        case FormShape:
            .editMode = .Shape
        case FormImage:
            .editMode = .Image
        case FormStep:
            .editMode = .Step
        case FormArrow:
            .editMode = .Arrow
        case FormLine:
            .editMode = .Line
        case FormPolygon:
            .editMode = .Polygon
        case FormText:
            .editMode = .Text
        case FormDraw:
            .editMode = .Draw
        case FormCallout:
            .editMode = .Callout
        }
    }

    func formToEditMode(f: IForm)->EditMode
    {
        #[Swag.Complete]
        switch f
        {
        case FormShape:
            return .Shape
        case FormArrow:
            return .Arrow
        case FormLine:
            return .Line
        case FormPolygon:
            return .Polygon
        case FormText:
            return .Text
        case FormDraw:
            return .Draw
        case FormStep:
            return .Step
        case FormImage:
            return .Image
        case FormCallout:
            return .Callout
        }

        unreachable
    }

    mtd editModeToModel(mode: EditMode)->IForm
    {
        var formItf: IForm

        #[Swag.Complete]
        switch mode
        {
        case Arrow:
            formItf = cast(IForm) .mdlFormArrow
        case Shape:
            formItf = cast(IForm) .mdlFormShape
        case Image:
            formItf = cast(IForm) .mdlFormImage
        case Step:
            formItf = cast(IForm) .mdlFormStep
        case Line:
            formItf = cast(IForm) .mdlFormLine
        case Polygon:
            formItf = cast(IForm) .mdlFormPolygon
        case Text:
            formItf = cast(IForm) .mdlFormText
        case Draw:
            formItf = cast(IForm) .mdlFormDraw
        case Callout:
            formItf = cast(IForm) .mdlFormCallout
        case Favorites, Selection:
            formItf = .mdlFavorite
        case Highlight:
            formItf = .mdlHighlight
        case PixSel:
            formItf = .mdlPixSel
        }

        return formItf
    }

    mtd newFormFromModel(mode: EditMode, clear = false)->IForm
    {
        // Clone the model of the given mode, whatever its concrete type
        let mdlItf  = .editModeToModel(mode)
        let mdlType = @kindof(mdlItf)
        let mdl     = cast(*BaseForm) Memory.new(mdlType)
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
        let mdlValue = cast(*BaseForm) Memory.new(@kindof(it))
        it.copy(mdlValue, cast(*BaseForm) @dataof(it))
        return mdlValue
    }
}
