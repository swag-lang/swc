#global public

using Core, Pixel

// Flags passed to Properties.addItem to select which sub-widgets a row gets.
#[Swag.EnumFlags]
enum AddItemFlags
{
    Zero = 0
    Name
    Description
}

// Per-row state flags.
#[Swag.EnumFlags]
enum ItemFlags
{
    Zero = 0
    NoSeparator
    NoFocus
    Section
    Category
    Expanded

    // Decorator rows injected from field attributes (properties.build.swg): a non-collapsible
    // divider label (Header), a blank vertical gap (Spacer) and an informational bar (Note).
    Header
    Spacer
    Note
}

// One row of the property grid: its window, the bound field (typeinfo + address, plus one
// address per instance for multi-selection), the editor sub-widgets, validation state and the
// tree bookkeeping. Rows are created by Properties.addItem (properties.build.swg) and stored flat
// in Properties.items, with the hierarchy tracked through the `parent` pointer.
struct PropertiesItem
{
    filter: String
    line:   #late *Wnd
    data:   #null *u8

    // Field address in every edited instance (multi-selection). [0] aliases `data`.
    // Empty or a single entry means a plain single-instance edit. Items under a dynamic
    // array are left single (their element addresses are not at a fixed struct offset).
    dataInstances: Array'(*u8)

    // When set, the editor writes each instance itself (e.g. a vector component or an
    // enum-flags bit), so hasChanged must not blindly copy the whole field over the
    // others — that would clobber the components/bits the user did not touch.
    selfPropagate: bool

    // "Reset to default" tracking (defaultstate.swg). defaultData points into the default-
    // constructed root instance at this field's fixed offset, i.e. the value the field is
    // initialized to in the struct declaration; it is null when there is no comparable default
    // (rows under a dynamic array, non-POD aggregates, ...). isModified caches whether the
    // current value differs from that default (recomputed on build and after every change);
    // revertButton is the lazily-created revert affordance shown while the row is modified.
    defaultData:    #null *u8
    isModified:     bool
    revertButton:   #late *IconButton
    arrayAddButton: #late *IconButton

    // Undo/redo snapshot (propertiesundo.swg): the last value the grid committed for this
    // field, kept per row so hasChanged can diff the new value against it and record one undo
    // command. Captured at build for every snapshot-able row (POD or String); left invalid for
    // rows that cannot be safely byte-copied (dynamic arrays, non-POD aggregates).
    undoValue: PropFieldValue

    type:      #null typeinfo
    typeValue: Swag.TypeValue
    parent:    #null *PropertiesItem
    flags:     ItemFlags
    userData0: #null *void
    userData1: #null *void

    label:       #late *Label
    description: String
    labelDesc:   #late *Label

    // Per-item validation (info/warning/error) shown as an inline colored message bar
    // stacked under the row.
    validation:      PropValidation
    validationMsg:   String
    validationLabel: #late *Label

    editBox:   #late *EditBox
    checkBox:  #late *CheckButton
    comboBox:  #late *ComboBox
    sliderBox: #late *SliderCtrl

    sigResize:  SigArray'func||(*PropertiesItem)
    sigRefresh: SigArray'func||(*PropertiesItem)

    ntfyItf: #null IPropertyNotify

    aniFocusBk:     BlendColor
    aniFocusBorder: BlendColor
    level:          u32
    numChilds:      u32
    section:        u32
    extendFocus:    f32 = 10

    // Grid only: height of the value cell (label + editor) on its own. The row grows below
    // it to host the validation message bar, so we keep the base height to restore/recompute.
    valueCellHeight: f32
}
