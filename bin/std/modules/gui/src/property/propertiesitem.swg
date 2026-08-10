#global public

using Core, Pixel

// Selects the standard labels created by [Properties.addItem].
#[Swag.EnumFlags]
enum PropertiesAddItemFlags
{
    None = 0        // Creates no standard label.
    Name            // Creates the field-name label.
    Description     // Creates the description label when reflection metadata supplies one.
}

// Controls the presentation and interaction of a [PropertiesItem].
#[Swag.EnumFlags]
enum PropertiesItemFlags
{
    None = 0        // Uses the default row behavior.
    NoSeparator     // Suppresses the row separator.
    NoFocus         // Excludes the row from keyboard navigation.
    Section         // Marks a top-level section row.
    Category        // Marks a category row.
    Expanded        // Shows the row's descendants.

    // Decorator rows injected from field attributes (properties.build.swg): a non-collapsible
    // divider label (Header), a blank vertical gap (Spacer) and an informational bar (Note).
    Header     // Marks a non-collapsible heading row.
    Spacer     // Marks a vertical spacing row.
    Note       // Marks an informational note row.
}

// One row of the property grid: its window, the bound field (typeinfo + address, plus one
// address per instance for multi-selection), the editor sub-widgets, validation state and the
// tree bookkeeping. Rows are created by Properties.addItem (properties.build.swg) and stored flat
// in Properties.items, with the hierarchy tracked through the `parent` pointer.
struct PropertiesItem
{
    internal
    filter: String
    #[Swag.Late]
    line: *Wnd          // Window hosting this row's editor.
    data: #null *u8     // Address of the bound field.

    // Field address in every edited instance (multi-selection). [0] aliases `data`.
    // Empty or a single entry means a plain single-instance edit. Items under a dynamic
    // array are left single (their element addresses are not at a fixed struct offset).
    internal
    dataInstances: Array'(*u8)

    // When set, the editor writes each instance itself (e.g. a vector component or an
    // enum-flags bit), so commitItemChange must not blindly copy the whole field over the
    // others — that would clobber the components/bits the user did not touch.
    internal
    selfPropagate: bool

    // "Reset to default" tracking (defaultstate.swg). defaultData points into the default-
    // constructed root instance at this field's fixed offset, i.e. the value the field is
    // initialized to in the struct declaration; it is null when there is no comparable default
    // (rows under a dynamic array, non-POD aggregates, ...). isModified caches whether the
    // current value differs from that default (recomputed on build and after every change);
    // revertButton is the lazily-created revert affordance shown while the row is modified.
    internal
    defaultData: #null *u8
    internal
    isModified:  bool
    #[Swag.Late]
    internal
    revertButton: *IconButton
    #[Swag.Late]
    internal
    arrayAddButton: *IconButton

    // Undo/redo snapshot (propertiesundo.swg): the last value the grid committed for this
    // field, kept per row so commitItemChange can diff the new value against it and record one undo
    // command. Captured at build for every snapshot-able row (POD or String); left invalid for
    // rows that cannot be safely byte-copied (dynamic arrays, non-POD aggregates).
    internal
    undoValue: PropFieldValue

    type:      #null typeinfo            // Bound field type.
    typeValue: Swag.TypeValue            // Reflection metadata of the bound field.
    parent:    #null *PropertiesItem     // Parent row, or null for a root.
    flags:     PropertiesItemFlags       // Presentation and interaction flags.
    userData0: #null *void               // User data0 associated with this value.
    userData1: #null *void               // User data1 associated with this value.

    #[Swag.Late]
    label:       *Label     // Primary row label.
    description: String     // Displayed field description.
    #[Swag.Late]
    labelDesc: *Label     // Description label.

    // Per-item validation (info/warning/error) shown as an inline colored message bar
    // stacked under the row.
    internal
    validation:    PropValidation
    internal
    validationMsg: String
    #[Swag.Late]
    internal
    validationLabel: *Label

    #[Swag.Late]
    {
        editBox:   *EditBox         // Edit box associated with this value.
        checkBox:  *CheckButton     // Check box associated with this value.
        comboBox:  *ComboBox        // Combo box associated with this value.
        sliderBox: *SliderCtrl      // Slider box associated with this value.
    }

    sigResize:  SigArray'func||(*PropertiesItem)     // Signal emitted when resize.
    sigRefresh: SigArray'func||(*PropertiesItem)     // Signal emitted when refresh.

    internal
    ntfyItf: #null IPropertyNotify

    internal
    aniFocusBk:     BlendColor
    internal
    aniFocusBorder: BlendColor
    internal
    level:          u32
    internal
    numChilds:      u32
    internal
    section:        u32
    internal
    extendFocus:    f32 = 10

    // Grid only: height of the value cell (label + editor) on its own. The row grows below
    // it to host the validation message bar, so we keep the base height to restore/recompute.
    internal
    valueCellHeight: f32
}

// Keeps public row state read-only while allowing the property-grid implementation to update it.
internal impl PropertiesItem
{
    mtd initialize(line: *Wnd, type: #null typeinfo, typeValue: Swag.TypeValue, data: #null *u8, parent: #null *PropertiesItem)
    {
        .line      = line
        .type      = type
        .typeValue = typeValue
        .data      = data
        .parent    = parent
    }

    mtd assignModified(modified: bool)
    {
        .isModified = modified
    }

    mtd assignLabel(label: *Label)
    {
        .label = label
    }

    mtd assignDescription(description: String)
    {
        .description = description
    }

    mtd assignDescriptionLabel(label: *Label)
    {
        .labelDesc = label
    }

    mtd assignValidation(state: PropValidation, message: String)
    {
        .validation    = state
        .validationMsg = message
    }

    mtd assignValidationLabel(label: *Label)
    {
        .validationLabel = label
    }

    mtd assignEditBox(edit: *EditBox)
    {
        .editBox = edit
    }

    mtd assignCheckBox(check: *CheckButton)
    {
        .checkBox = check
    }

    mtd assignComboBox(combo: *ComboBox)
    {
        .comboBox = combo
    }

    mtd assignSliderBox(slider: *SliderCtrl)
    {
        .sliderBox = slider
    }
}
