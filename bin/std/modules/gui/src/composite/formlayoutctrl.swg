#global public

using Core

// Selects where a form places labels relative to their fields.
enum FormLabelPlacement
{
    Above     // Places each label above its field.
    Left      // Places labels in a shared column to the left of fields.
}

// Configures the geometry shared by every row in a [[Gui.FormLayoutCtrl]].
struct FormLayoutOptions
{
    labelPlacement: FormLabelPlacement = Above         // Label placement used by every row.
    labelWidth                         = 112.0'f32     // Width of the label column in `Left` mode.
    labelHeight                        = 22.0'f32      // Height reserved for each label.
    fieldHeight                        = 34.0'f32      // Minimum height reserved for each field.
    helpHeight                         = 20.0'f32      // Height reserved for optional help text.
    labelSpacing                       = 4.0'f32       // Gap between a label and its field.
    controlSpacing                     = 8.0'f32       // Gap between a field and its optional action.
    helpSpacing                        = 4.0'f32       // Gap before optional help text.
    rowSpacing                         = 12.0'f32      // Gap between consecutive rows.
}

// Describes one field row owned and arranged by a [[Gui.FormLayoutCtrl]].
struct FormLayoutRow
{
    readonly
    {
        label:  *Label           // Label created and owned by the form.
        field:  *Wnd             // Caller-created field owned by the form.
        action: #null *Wnd       // Optional trailing action owned by the form.
        help:   #null *Label     // Optional explanatory label owned by the form.
    }
}

// Arranges labeled fields from a compact row description instead of fixed coordinates.
//
// Create controls with the form as their parent, then register each row with
// [[Gui.FormLayoutCtrl.addField]]. The caller retains the concrete control pointers;
// the form owns only their layout.
struct FormLayoutCtrl
{
    using wnd: Wnd     // Embedded wnd state.

    options: FormLayoutOptions     // Geometry applied to all rows.

    readonly
    {
        rows:          Array'FormLayoutRow     // Rows in display order.
        contentHeight: f32                     // Height required by the latest layout pass.
    }
}

impl IWnd for FormLayoutCtrl
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .computeLayout()
        .wnd.IWnd.onResizeEvent(evt)
    }
}

private impl FormLayoutCtrl
{
    mtd rowFieldHeight(row: const *FormLayoutRow, available: Math.Point)->f32
    {
        let fieldHint = row.field.measure(available)
        var result    = Math.max(.options.fieldHeight, fieldHint.preferred.y)
        if row.action
        {
            let actionHint = row.action.measure(available)
            result = Math.max(result, actionHint.preferred.y)
        }

        return result
    }

    mtd arrangeRowAbove(row: const *FormLayoutRow, client: Math.Rectangle, y: f32)->f32
    {
        row.label.arrange({client.x, y, client.width, .options.labelHeight})
        var cursor = y + .options.labelHeight + .options.labelSpacing
        let height = .rowFieldHeight(row, {client.width, client.height})

        var actionWidth = 0'f32
        if row.action
        {
            let action = notnull row.action
            actionWidth = action.measure({client.width, height}).preferred.x
            actionWidth = Math.max(actionWidth, action.minSize.x)
        }

        let actionGap  = row.action ? .options.controlSpacing : 0
        let fieldWidth = Math.max(0, client.width - actionWidth - actionGap)
        row.field.arrange({client.x, cursor, fieldWidth, height})
        if row.action do
            row.action.arrange({client.x + fieldWidth + actionGap, cursor, actionWidth, height})
        cursor += height

        if row.help
        {
            cursor += .options.helpSpacing
            row.help.arrange({client.x, cursor, client.width, .options.helpHeight})
            cursor += .options.helpHeight
        }

        return cursor
    }

    mtd arrangeRowLeft(row: const *FormLayoutRow, client: Math.Rectangle, y: f32)->f32
    {
        let fieldX         = client.x + .options.labelWidth + .options.labelSpacing
        let availableWidth = Math.max(0, client.width - .options.labelWidth - .options.labelSpacing)
        let height         = .rowFieldHeight(row, {availableWidth, client.height})
        row.label.arrange({client.x, y, .options.labelWidth, height})

        var actionWidth = 0'f32
        if row.action
        {
            let action = notnull row.action
            actionWidth = action.measure({availableWidth, height}).preferred.x
            actionWidth = Math.max(actionWidth, action.minSize.x)
        }

        let actionGap  = row.action ? .options.controlSpacing : 0
        let fieldWidth = Math.max(0, availableWidth - actionWidth - actionGap)
        row.field.arrange({fieldX, y, fieldWidth, height})
        if row.action do
            row.action.arrange({fieldX + fieldWidth + actionGap, y, actionWidth, height})
        var cursor = y + height

        if row.help
        {
            cursor += .options.helpSpacing
            row.help.arrange({fieldX, cursor, availableWidth, .options.helpHeight})
            cursor += .options.helpHeight
        }

        return cursor
    }
}

impl FormLayoutCtrl
{
    // Creates an empty form layout inside `parent`.
    #[Swag.Discardable]
    func create(parent: *Wnd, options: FormLayoutOptions = {}, position: Math.Rectangle = {})->*FormLayoutCtrl
    {
        Debug.assert(parent != null)
        let result = Wnd.create'FormLayoutCtrl(parent, null, position)
        result.options         = options
        result.backgroundStyle = .Transparent
        return result
    }

    // Appends a labeled field and returns its row index.
    //
    // `field` and `action` must already be children of this form. The form creates
    // and owns the label and optional help label. The concrete field remains
    // directly available to the caller through the pointer passed here.
    #[Swag.Discardable]
    mtd addField(label: string, field: *Wnd, action: #null *Wnd = null, help: #null string = null)->u64
    {
        Debug.assert(field.parent == me, "form field needs the form as its parent")
        Debug.assert(!action or action.parent == me, "form action needs the form as its parent")

        var row = FormLayoutRow{
            label: Label.create(me, label),
            field: field,
            action: action}
        row.label.setTextAlignment(.Left, .Center)
        if help
        {
            row.help = Label.create(me, help, flags: .WordWrap | .SecondaryText)
            row.help.setTextAlignment(.Left, .Top)
        }

        let result = .rows.count
        .rows.add(#move row)
        .invalidateLayout()
        return result
    }

    // Removes every row and destroys its controls.
    mtd clear()
    {
        for &row in .rows
        {
            row.label.destroy()
            row.field.destroy()
            row.action?.destroy()
            row.help?.destroy()
        }

        .rows.clear()
        .contentHeight = 0
        .invalidateLayout()
    }

    // Arranges every row inside the padded client rectangle.
    mtd computeLayout()
    {
        let client = .paddedClientRect()
        var cursor = client.y
        for &row, [index] in .rows
        {
            cursor = .options.labelPlacement == .Above ?
                     .arrangeRowAbove(&row, client, cursor) :
                     .arrangeRowLeft(&row, client, cursor)
            if index + 1 < .rows.count do
                cursor += .options.rowSpacing
        }

        .contentHeight = Math.max(0, cursor - client.y)
    }
}
