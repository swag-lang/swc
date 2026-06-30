#global public
using Core, Pixel

// Signature of a custom editor factory. Given a field 'value' (typeinfo + name) whose storage
// is at 'data', build its editor row(s) under 'parent' and return the created item — exactly
// like the built-in construct* methods. The canonical recipe is: call list.addItem(value, data,
// parent), create the editor widget(s) under item.line, wire their change callbacks to
// list.hasChanged(item), and add an item.sigRefresh handler that pushes the current value back
// into the widget(s). See values/color.swg and values/vector.swg for full examples.
//
// This is the non-intrusive equivalent of implementing IPropertyValue on a type: it lets ANY
// type (including primitives, enums, or types you do not own) get a bespoke representation in a
// property grid, registered from the outside.
alias PropertyEditor = func||(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem

// One type -> editor mapping in a registry.
struct PropertyEditorEntry
{
    type:    typeinfo
    factory: PropertyEditor
}

// Process-wide registry of custom editors, consulted by every Properties grid. A per-grid
// registry (Properties.editors, see registerEditor) takes precedence over this one. Usually
// populated once at startup with Properties.registerGlobalEditor.
var g_PropertyEditors: Array'PropertyEditorEntry

impl Properties
{
    // Register a custom editor for 'type' on THIS grid only. It takes precedence over the
    // global registry, over an IPropertyValue implementation on the type, and over the
    // built-in editors. Registering the same type again replaces the previous editor.
    mtd registerEditor(type: typeinfo, factory: PropertyEditor)
    {
        registerEditorIn(&.editors, type, factory)
    }

    // Register a custom editor for 'type' on ALL grids. A per-grid registration (registerEditor)
    // for the same type still wins. Registering the same type again replaces the previous editor.
    func registerGlobalEditor(type: typeinfo, factory: PropertyEditor)
    {
        registerEditorIn(&g_PropertyEditors, type, factory)
    }

    // Look up a custom editor for 'type': the per-grid registry first, then the global one.
    // Returns null when no editor is registered, in which case the built-in dispatch applies.
    mtd findEditor(type: typeinfo)->PropertyEditor
    {
        let f = findEditorIn(.editors, type)
        if f do
            return f
        return findEditorIn(g_PropertyEditors, type)
    }
}

// Add (or replace) a 'type -> factory' mapping in 'reg'.
fileprivate func registerEditorIn(reg: *Array'PropertyEditorEntry, type: typeinfo, factory: PropertyEditor)
{
    foreach &e in dref reg
    {
        if e.type == type
        {
            e.factory = factory
            return
        }
    }

    reg.add({type, factory})
}

// Find the factory registered for 'type' in 'reg', or null.
fileprivate func findEditorIn(reg: Array'PropertyEditorEntry, type: typeinfo)->PropertyEditor
{
    foreach e in reg
    {
        if e.type == type do
            return e.factory
    }

    return null
}
