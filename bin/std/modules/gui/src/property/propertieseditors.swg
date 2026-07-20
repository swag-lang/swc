#global public
using Core, Pixel

// A pluggable property editor. Register an implementing type with Properties.registerEditor
// (typically from a #init block); for each field the grid asks every registered editor whether
// it handles the field's type via canEdit, then builds the row via construct. This mirrors the
// image codec architecture (IImageDecoder / IImageEncoder): an interface + a type registry +
// per-use instantiation.
//
// It is non-intrusive: the edited type is never touched. It lets ANY type (including primitives,
// enums, the built-in Color/vector types, or types you do not own) get a bespoke editor,
// registered from the outside. Because canEdit receives the type, one editor can claim a whole
// FAMILY of types (every enum, every type carrying a given attribute, a set of related structs),
// not just a single one — something a type-keyed map cannot express.
public interface IPropertyEditor
{
    // Return true if this editor should handle a field of type 'type'.
    mtd canEdit(type: #null typeinfo)->bool;

    // Build the editor row(s) for 'value' (the field at 'data') under 'parent' and return the
    // created item — exactly like the built-in construct* methods. The recipe: call
    // list.addItem(value, data, parent), create the editor widget(s) under item.line, wire their
    // change callbacks to list.hasChanged(item), and add an item.sigRefresh handler that pushes
    // the current value back into the widget(s). See values/color.swg and values/vector.swg.
    //
    // An editor is a stateless singleton: it is invoked on a null instance (like canEdit), so
    // 'me' carries no per-field state — read any per-field configuration from 'value' (its
    // attributes), and wire 'data'/'item'/'list' into the widget callbacks.
    mtd construct(list: *Properties, value: Swag.TypeValue, data: #null [*] u8, parent: #null *PropertiesItem)->*PropertiesItem;
}

// One registered editor: the implementing type (used to instantiate a fresh editor per field)
// plus a null-pointer interface used only for the canEdit capability query. Same shape as
// ImageDecoder / ImageEncoder.
struct PropertyEditorReg
{
    type: const *Swag.TypeInfoStruct
    itf:  IPropertyEditor
}

impl Properties
{
    // Process-wide registry of custom editors, consulted by every grid before the built-in
    // editors. Mirrors Image.decoders / Image.encoders.
    var editors: Array'PropertyEditorReg

    // Register a custom editor type T (which must implement IPropertyEditor) for ALL grids.
    // Call once, typically from a #init block — mirrors Image.addDecoder / Image.addEncoder.
    //
    // The body is kept to #typeof/@mkinterface and delegates the registry mutation to the
    // non-generic addEditor: this generic is instantiated in the CALLER's module, which cannot
    // see the module-internal 'editors' static — addEditor, compiled here, can.
    func(T) registerEditor()
    {
        #assert(Reflection.hasInterface(#typeof(T), IPropertyEditor))
        Properties.addEditor(#typeof(T), @mkinterface(null, #typeof(T), IPropertyEditor))
    }

    // Append a {type, itf} entry to the registry. Public so the generic registerEditor above can
    // call it from any module; the 'editors' static itself stays module-internal.
    func addEditor(type: const *Swag.TypeInfoStruct, itf: IPropertyEditor)
    {
        var reg: PropertyEditorReg = undefined
        reg.type = type
        reg.itf  = itf
        editors.add(reg)
    }

    // Find the editor that claims 'type', or null. Scans newest-first so a later registration
    // overrides an earlier one for the same type — this is what lets a user editor replace a
    // built-in (Color/vector) editor, which all live in this one registry.
    func findEditor(type: #null typeinfo)->#null *PropertyEditorReg
    {
        var found: #null *PropertyEditorReg
        var i     = Properties.editors.count
        while i > 0
        {
            i -= 1
            if Properties.editors[i].itf.canEdit(type)
            {
                found = &Properties.editors[i]
                break
            }
        }

        return found
    }
}
