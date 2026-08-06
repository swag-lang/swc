#global public

using Core, Pixel

// Selects where a form places labels relative to their fields.
enum FormLabelPlacement
{
    Above     // Places each label above its field.
    Left      // Places labels in a shared column to the left of fields.
}

// Configures the geometry and the label presentation shared by every row in a
// [[Gui.FormLayoutCtrl]].
//
// The form creates its own labels, so `labelFont` and `labelFlags` are how a surface gives them
// its own emphasis instead of restyling them one by one after the fact.
struct FormLayoutOptions
{
    labelPlacement: FormLabelPlacement = Above         // Label placement used by every row.
    labelWidth                         = 112.0'f32     // Minimum width of the label column in `Left` mode.
    labelHeight                        = 22.0'f32      // Height reserved for each label.
    fieldHeight                        = 34.0'f32      // Minimum height reserved for each field.
    helpHeight                         = 20.0'f32      // Minimum height reserved for optional help text.
    labelSpacing                       = 4.0'f32       // Gap between a label and its field.
    controlSpacing                     = 8.0'f32       // Gap between a field and its optional action.
    helpSpacing                        = 4.0'f32       // Gap before optional help text.
    rowSpacing                         = 12.0'f32      // Gap between consecutive rows.
    labelFont:      #null *Font        = null          // Font applied to every created label, or the theme font.
    labelFlags:     LabelFlags         = None          // Presentation options applied to every created label.
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
// The `addTextField`, `addPasswordField`, and `addChoiceField` builders create a control,
// append its labeled row, and return the concrete control, so a caller never looks a field
// up by name. Add the optional trailing control of the row that was just appended with
// [[Gui.FormLayoutCtrl.addRowAction]] or [[Gui.FormLayoutCtrl.addRowChoice]]. Use
// [[Gui.FormLayoutCtrl.addField]] directly for a control the builders do not create.
//
// The form owns the labels it creates and the layout of every row; the caller keeps the
// concrete control pointers.
//
// ```swag
// let form = FormLayoutCtrl.create(parent)
// let path = form.addTextField("CONTAINER FILE", placeholder: "C:\\private.scrypt")
// let browse = form.addRowAction("Browse")
// let password = form.addPasswordField("PASSWORD")
// form.computeLayout()
// ```
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
    // Returns the height the help text of `row` needs at `width`, never below its option.
    //
    // Help text wraps, so its height belongs to the width it will be drawn at: a sentence
    // that fits on two lines in one language takes three in another, and a reserved
    // height would cut the last one off.
    mtd rowHelpHeight(row: const *FormLayoutRow, width: f32)->f32
    {
        if !row.help do
            return 0
        return Math.max(.options.helpHeight, row.help.measure({width, 0}).preferred.y)
    }

    // Returns the width of the label column in `Left` mode, never below its option.
    mtd labelColumnWidth()->f32
    {
        var result = .options.labelWidth
        for &row in .rows do
            result = Math.max(result, row.label.measure({}).preferred.x)
        return result
    }

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
            let action = row.action!
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
            let helpHeight = .rowHelpHeight(row, client.width)
            cursor += .options.helpSpacing
            row.help.arrange({client.x, cursor, client.width, helpHeight})
            cursor += helpHeight
        }

        return cursor
    }

    mtd arrangeRowLeft(row: const *FormLayoutRow, client: Math.Rectangle, y: f32, labelWidth: f32)->f32
    {
        let fieldX         = client.x + labelWidth + .options.labelSpacing
        let availableWidth = Math.max(0, client.width - labelWidth - .options.labelSpacing)
        let height         = .rowFieldHeight(row, {availableWidth, client.height})
        row.label.arrange({client.x, y, labelWidth, height})

        var actionWidth = 0'f32
        if row.action
        {
            let action = row.action!
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
            let helpHeight = .rowHelpHeight(row, availableWidth)
            cursor += .options.helpSpacing
            row.help.arrange({fieldX, cursor, availableWidth, helpHeight})
            cursor += helpHeight
        }

        return cursor
    }

    // Gives the row appended last its single trailing control.
    mtd attachToLastRow(control: *Wnd)
    {
        Debug.assert(!.rows.isEmpty(), "a trailing control needs a field row to extend")
        let row = .rows.backPtr()
        Debug.assert(row.action == null, "a form row holds a single trailing control")
        row.action = control
        .invalidateLayout()
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
            label: Label.create(me, label, flags: .options.labelFlags),
            field: field,
            action: action}
        row.label.setTextAlignment(.Left, .Center)
        if .options.labelFont do
            row.label.style.setFont(.options.labelFont!, .Regular)
        if help
        {
            row.help = Label.create(me, help, flags: .WordWrap | .SecondaryText | .AutoHeight)
            row.help.setTextAlignment(.Left, .Top)
        }

        let result = .rows.count
        .rows.add(#move row)
        .invalidateLayout()
        return result
    }

    // Creates an editable text field, appends its labeled row, and returns the editor.
    //
    // `icon` is displayed inside the editor when it refers to a valid atlas frame.
    mtd addTextField(label: string, text: string = "", placeholder: #null string = null, help: #null string = null, icon: Icon = {}, id: #null WndId = null)->*EditBox
    {
        let result = EditBox.create(me, text, id: id)
        result.setPlaceholder(placeholder)
        if icon.isValid() do
            result.setIcon(icon)
        discard .addField(label, result, null, help)
        return result
    }

    // Creates a masked password field, appends its labeled row, and returns the editor.
    mtd addPasswordField(label: string, placeholder: #null string = null, help: #null string = null, icon: Icon = {}, id: #null WndId = null)->*PasswordEdit
    {
        let result = PasswordEdit.create(me, id: id)
        result.setPlaceholder(placeholder)
        if icon.isValid() do
            result.setIcon(icon)
        discard .addField(label, result, null, help)
        return result
    }

    // Creates a selection-only field, appends its labeled row, and returns the combo box.
    //
    // The combo box starts empty and without a selection. Fill it with
    // [[Gui.ComboBox.addItem]], then select the entry the form should open on.
    mtd addChoiceField(label: string, help: #null string = null, id: #null WndId = null)->*ComboBox
    {
        let result = ComboBox.create(me, id: id)
        discard .addField(label, result, null, help)
        return result
    }

    // Adds the trailing button of the row appended last and returns it.
    //
    // The button shares the height of its field and keeps its preferred width. A row holds a
    // single trailing control, so this cannot follow [[Gui.FormLayoutCtrl.addRowChoice]] on
    // the same row.
    mtd addRowAction(text: string, icon: Icon = {}, id: #null WndId = null)->*PushButton
    {
        let result = PushButton.create(me, text, {}, id)
        if icon.isValid() do
            result.setIcon(icon)
        .attachToLastRow(result)
        return result
    }

    // Adds the trailing selector of the row appended last and returns it.
    //
    // Use it for the unit or qualifier of a value the field itself holds, such as the size
    // unit beside a capacity. A row holds a single trailing control.
    mtd addRowChoice(id: #null WndId = null)->*ComboBox
    {
        let result = ComboBox.create(me, id: id)
        .attachToLastRow(result)
        return result
    }

    // Replaces the label of row `index`.
    //
    // The form owns its labels, so this is how a surface says a field name again after a
    // language switch without rebuilding the form and losing what the fields hold.
    mtd setRowLabel(index: u64, label: string)
    {
        Debug.assert(index < .rows.count, "no such form row")
        .rows[index].label.setText(label)
        .invalidateLayout()
    }

    // Replaces the help text of row `index`, which must already have one.
    mtd setRowHelp(index: u64, help: string)
    {
        Debug.assert(index < .rows.count, "no such form row")
        let row = &.rows[index]
        Debug.assert(row.help != null, "this form row carries no help text")
        row.help!.setText(help)
        .invalidateLayout()
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

        // In `Left` mode the label column is shared, so it is measured once for the whole
        // form: a column sized row by row would leave the fields on a ragged edge.
        let labelWidth = .options.labelPlacement == .Left ? .labelColumnWidth() : 0

        var cursor = client.y
        for &row, [index] in .rows
        {
            cursor = .options.labelPlacement == .Above ? .arrangeRowAbove(&row, client, cursor) : .arrangeRowLeft(&row, client, cursor, labelWidth)
            if index + 1 < .rows.count do
                cursor += .options.rowSpacing
        }

        .contentHeight = Math.max(0, cursor - client.y)
    }
}
