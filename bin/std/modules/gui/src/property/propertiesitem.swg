#global public
using Core, Pixel

// Flags passed to Properties.addItem to select which sub-widgets a row gets.
#[Swag.EnumFlags]
enum AddItemFlags
{
    Zero        = 0
    Name
    Description
}

// Per-row state flags.
#[Swag.EnumFlags]
enum ItemFlags
{
    Zero        = 0
    NoSeparator
    NoFocus
    Section
    Category
    Expanded
}

// One row of the property grid: its window, the bound field (typeinfo + address, plus one
// address per instance for multi-selection), the editor sub-widgets, validation state and the
// tree bookkeeping. Rows are created by Properties.addItem (properties.build.swg) and stored flat
// in Properties.items, with the hierarchy tracked through the `parent` pointer.
struct PropertiesItem
{
    filter:             String
    line:               *Wnd
    data:               *u8
    // Field address in every edited instance (multi-selection). [0] aliases `data`.
    // Empty or a single entry means a plain single-instance edit. Items under a dynamic
    // array are left single (their element addresses are not at a fixed struct offset).
    dataInstances:      Array'(*u8)
    // When set, the editor writes each instance itself (e.g. a vector component or an
    // enum-flags bit), so hasChanged must not blindly copy the whole field over the
    // others — that would clobber the components/bits the user did not touch.
    selfPropagate:      bool
    type:               typeinfo
    typeValue:          Swag.TypeValue
    parent:             *PropertiesItem
    flags:              ItemFlags
    userData0:          *void
    userData1:          *void

    label:              *Label
    description:        String
    labelDesc:          *Label

    // Per-item validation (info/warning/error) shown as an inline colored message bar
    // stacked under the row.
    validation:         PropValidation
    validationMsg:      String
    validationLabel:    *Label

    editBox:            *EditBox
    checkBox:           *CheckButton
    comboBox:           *ComboBox
    sliderBox:          *SliderCtrl

    sigResize:          SigArray'func||(*PropertiesItem)
    sigRefresh:         SigArray'func||(*PropertiesItem)

    ntfyItf:            IPropertyNotify

    aniFocusBk:         BlendColor
    aniFocusBorder:     BlendColor
    level:              u32
    numChilds:          u32
    section:            u32
    extendFocus:        f32 = 10

    // Grid only: height of the value cell (label + editor) on its own. The row grows below
    // it to host the validation message bar, so we keep the base height to restore/recompute.
    valueCellHeight:    f32
}
