#global public

using Core, Pixel

// Flags passed to Properties.addItem to select which sub-widgets a row gets.
#[Swag.EnumFlags]
enum AddItemFlags
{
    Zero = 0        // No flags are enabled.
    Name            // Enables name.
    Description     // Enables description.
}

// Per-row state flags.
#[Swag.EnumFlags]
enum ItemFlags
{
    Zero = 0        // No flags are enabled.
    NoSeparator     // Enables no separator.
    NoFocus         // Enables no focus.
    Section         // Enables section.
    Category        // Enables category.
    Expanded        // Enables expanded.

    // Decorator rows injected from field attributes (properties.build.swg): a non-collapsible
    // divider label (Header), a blank vertical gap (Spacer) and an informational bar (Note).
    Header     // Enables header.
    Spacer     // Enables spacer.
    Note       // Enables note.
}

// One row of the property grid: its window, the bound field (typeinfo + address, plus one
// address per instance for multi-selection), the editor sub-widgets, validation state and the
// tree bookkeeping. Rows are created by Properties.addItem (properties.build.swg) and stored flat
// in Properties.items, with the hierarchy tracked through the `parent` pointer.
struct PropertiesItem
{
    filter: String     // Filter associated with this value.
    #[Swag.Late]
    line: *Wnd          // Line associated with this value.
    data: #null *u8     // Data associated with this value.

    // Field address in every edited instance (multi-selection). [0] aliases `data`.
    // Empty or a single entry means a plain single-instance edit. Items under a dynamic
    // array are left single (their element addresses are not at a fixed struct offset).
    dataInstances: Array'(*u8)     // Data instances associated with this value.

    // When set, the editor writes each instance itself (e.g. a vector component or an
    // enum-flags bit), so hasChanged must not blindly copy the whole field over the
    // others — that would clobber the components/bits the user did not touch.
    selfPropagate: bool     // Self propagate associated with this value.

    // "Reset to default" tracking (defaultstate.swg). defaultData points into the default-
    // constructed root instance at this field's fixed offset, i.e. the value the field is
    // initialized to in the struct declaration; it is null when there is no comparable default
    // (rows under a dynamic array, non-POD aggregates, ...). isModified caches whether the
    // current value differs from that default (recomputed on build and after every change);
    // revertButton is the lazily-created revert affordance shown while the row is modified.
    defaultData: #null *u8     // Default data associated with this value.
    isModified:  bool          // Whether this value is modified.
    #[Swag.Late]
    revertButton: *IconButton     // Revert button associated with this value.
    #[Swag.Late]
    arrayAddButton: *IconButton     // Array add button associated with this value.

    // Undo/redo snapshot (propertiesundo.swg): the last value the grid committed for this
    // field, kept per row so hasChanged can diff the new value against it and record one undo
    // command. Captured at build for every snapshot-able row (POD or String); left invalid for
    // rows that cannot be safely byte-copied (dynamic arrays, non-POD aggregates).
    undoValue: PropFieldValue     // Undo value associated with this value.

    type:      #null typeinfo            // Type associated with this value.
    typeValue: Swag.TypeValue            // Type value associated with this value.
    parent:    #null *PropertiesItem     // Parent associated with this value.
    flags:     ItemFlags                 // Flags associated with this value.
    userData0: #null *void               // User data0 associated with this value.
    userData1: #null *void               // User data1 associated with this value.

    #[Swag.Late]
    label:       *Label     // Label associated with this value.
    description: String     // Description associated with this value.
    #[Swag.Late]
    labelDesc: *Label     // Label desc associated with this value.

    // Per-item validation (info/warning/error) shown as an inline colored message bar
    // stacked under the row.
    validation:    PropValidation     // Validation associated with this value.
    validationMsg: String             // Validation msg associated with this value.
    #[Swag.Late]
    validationLabel: *Label     // Validation label associated with this value.

    #[Swag.Late]
    {
        editBox:   *EditBox         // Edit box associated with this value.
        checkBox:  *CheckButton     // Check box associated with this value.
        comboBox:  *ComboBox        // Combo box associated with this value.
        sliderBox: *SliderCtrl      // Slider box associated with this value.
    }

    sigResize:  SigArray'func||(*PropertiesItem)     // Signal emitted when resize.
    sigRefresh: SigArray'func||(*PropertiesItem)     // Signal emitted when refresh.

    ntfyItf: #null IPropertyNotify     // Ntfy itf associated with this value.

    aniFocusBk:     BlendColor     // Ani focus bk associated with this value.
    aniFocusBorder: BlendColor     // Ani focus border associated with this value.
    level:          u32            // Level associated with this value.
    numChilds:      u32            // Num childs associated with this value.
    section:        u32            // Section associated with this value.
    extendFocus:    f32 = 10       // Extend focus associated with this value.

    // Grid only: height of the value cell (label + editor) on its own. The row grows below
    // it to host the validation message bar, so we keep the base height to restore/recompute.
    valueCellHeight: f32     // Value cell height associated with this value.
}
