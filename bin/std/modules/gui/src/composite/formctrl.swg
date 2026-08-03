#global public

using Core

// Selects the control created for a declarative form field.
enum FormFieldKind
{
    Text        // Creates a single-line [[Gui.EditBox]].
    Password    // Creates a plaintext-safe [[Gui.PasswordEdit]].
    Choice      // Creates a selection-only [[Gui.ComboBox]].
}

// Describes one choice in a declarative form field.
struct FormChoice
{
    text: String                 // Text displayed by the combo box; owned by the definition.
    id:   #null WndId = null    // Optional stable identifier for the choice.
}

// Describes one field materialized by [[Gui.FormCtrl.create]].
//
// String values are read only while the form is being created. The resulting
// controls own their displayed contents.
struct FormFieldDefinition
{
    id:           WndId = ""                    // Stable identifier used to retrieve the field.
    label:        string = ""                   // Label displayed beside or above the control.
    kind:         FormFieldKind = Text          // Kind of control to create.
    initialText:  string = ""                   // Initial text for a text field.
    placeholder:  string = ""                   // Placeholder for text and password fields.
    help:         string = ""                   // Optional explanatory text below the field.
    actionText:   string = ""                   // Optional trailing action-button text.
    choices:      Array'FormChoice               // Primary choices for `Choice`, or trailing choices for another kind.
    selectedIndex = 0'u32                        // Initially selected primary or trailing choice index.
}

// Stores the typed controls created for one declarative field.
struct FormField
{
    readonly
    {
        id:       String                 // Stable field identifier.
        kind:     FormFieldKind = Text   // Materialized control kind.
        control:  *Wnd = undefined       // Generic field control.
        edit:     #null *EditBox         // Text editor when `kind` is `Text`.
        password: #null *PasswordEdit    // Password editor when `kind` is `Password`.
        choice:   #null *ComboBox        // Combo box when `kind` is `Choice`.
        action:   #null *PushButton      // Optional trailing action button.
        accessoryChoice: #null *ComboBox // Optional trailing choice control.
    }
}

// Materializes a typed form from field descriptions and arranges it automatically.
//
// Use [[Gui.FormCtrl.findField]], [[Gui.FormCtrl.textField]],
// [[Gui.FormCtrl.passwordField]], or [[Gui.FormCtrl.choiceField]] to retain typed
// access without manually constructing every label and control.
struct FormCtrl
{
    using layout: FormLayoutCtrl     // Embedded form-layout behavior.

    readonly fields: Array'FormField     // Materialized fields in declaration order.

    sigAction: SigArray'func||(*FormCtrl, WndId)     // Emitted by a field's optional action button.
}

private impl FormCtrl
{
    mtd addDefinition(definition: const *FormFieldDefinition)
    {
        Debug.assert(@countof(definition.id) != 0, "form field identifier cannot be empty")
        Debug.assert(.findField(definition.id) == null, "form field identifiers must be unique")

        var field: FormField
        field.id   = definition.id
        field.kind = definition.kind

        switch #complete definition.kind
        {
        case .Text:
            field.edit = EditBox.create(me, definition.initialText, id: definition.id)
            if @countof(definition.placeholder) do
                field.edit.setPlaceholder(definition.placeholder)
            field.control = field.edit

        case .Password:
            field.password = PasswordEdit.create(me, id: definition.id)
            if @countof(definition.placeholder) do
                field.password.setPlaceholder(definition.placeholder)
            field.control = field.password

        case .Choice:
            field.choice = ComboBox.create(me, id: definition.id)
            for &choice in definition.choices do
                field.choice.addItem(choice.text.toString(), choice.id)
            if field.choice.items.count
            {
                let selected = Math.min(definition.selectedIndex,
                                        cast(u32) (field.choice.items.count - 1))
                field.choice.setSelectedIndex(selected, false)
            }
            field.control = field.choice
        }

        if @countof(definition.actionText)
        {
            field.action = PushButton.create(me, definition.actionText, id: definition.id)
            field.action.sigPressed += func|form = me|(button)
            {
                form.sigAction.call(form, button.id)
            }
        }
        elif definition.kind != .Choice and !definition.choices.isEmpty()
        {
            field.accessoryChoice = ComboBox.create(me)
            for &choice in definition.choices do
                field.accessoryChoice.addItem(choice.text.toString(), choice.id)
            let selected = Math.min(definition.selectedIndex,
                                    cast(u32) (field.accessoryChoice.items.count - 1))
            field.accessoryChoice.setSelectedIndex(selected, false)
        }

        let control = field.control
        let accessory = field.action ? cast(#null *Wnd) field.action : field.accessoryChoice
        .fields.add(#move field)
        discard .addField(definition.label, control, accessory,
                          @countof(definition.help) ? definition.help : null)
    }
}

impl FormCtrl
{
    // Creates and materializes a form inside `parent`.
    #[Swag.Discardable]
    func create(parent: *Wnd, definitions: const [..] FormFieldDefinition,
                options: FormLayoutOptions = {}, position: Math.Rectangle = {})->*FormCtrl
    {
        Debug.assert(parent != null)
        let result = Wnd.create'FormCtrl(parent, null, position)
        result.options         = options
        result.backgroundStyle = .Transparent
        result.fields.reserve(@countof(definitions))
        for &definition in definitions do
            result.addDefinition(&definition)
        result.computeLayout()
        return result
    }

    // Finds a materialized field by identifier.
    mtd findField(id: WndId)->#null const *FormField
    {
        for &field in .fields where field.id == id do
            return &field
        return null
    }

    // Returns the text editor for `id`, or null when it has another kind.
    mtd textField(id: WndId)->#null *EditBox
    {
        let field = .findField(id)
        return field ? field.edit : null
    }

    // Returns the password editor for `id`, or null when it has another kind.
    mtd passwordField(id: WndId)->#null *PasswordEdit
    {
        let field = .findField(id)
        return field ? field.password : null
    }

    // Returns the choice control for `id`, or null when it has another kind.
    mtd choiceField(id: WndId)->#null *ComboBox
    {
        let field = .findField(id)
        return field ? field.choice : null
    }
}
