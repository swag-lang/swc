#global public

using Core, Pixel

// Builds the editor row of the property fields whose type it claims.
//
// Register an implementing type with [[Gui.Properties.registerEditor]], typically from a `#init`
// block. For each field, the grid asks every registered editor whether it handles the field's
// type through [[Gui.IPropertyEditor.canEdit]], then builds the row through
// [[Gui.IPropertyEditor.construct]]. This mirrors the image codec architecture: an interface, a
// type registry, and per-use instantiation.
//
// The edited type is never touched, so any type, including primitives, enums, the built-in color
// and vector types, or types you do not own, can get a bespoke editor registered from the
// outside. Because `canEdit` receives the type, one editor can claim a whole family of types —
// every enum, every type carrying a given attribute, a set of related structures — which a
// type-keyed map cannot express.
interface IPropertyEditor
{
    // Returns whether this editor handles a field of type `type`.
    mtd canEdit(type: typeinfo?)->bool

    // Builds the editor rows for `value`, the field at `data`, under `parent`, and returns the created row.
    //
    // The recipe: call [[Gui.Properties.addItem]] with `value`, `data`, and `parent`, create the
    // editor widgets under the row's line, wire their change callbacks to
    // [[Gui.Properties.commitItemChange]], and add a `sigRefresh` handler to the row that pushes
    // the current value back into the widgets. See `values/color.swg` and `values/vector.swg`.
    //
    // An editor is a stateless singleton invoked on a null instance, like `canEdit`, so `me`
    // carries no per-field state: read any per-field configuration from the attributes of
    // `value`, and wire `data`, the row, and `list` into the widget callbacks.
    mtd construct(list: *Properties, value: Swag.TypeValue, data: [*] u8?, parent: *PropertiesItem?)->*PropertiesItem
}

// One registered editor of the property grid.
//
// It holds the implementing type, instantiated once per edited field, and an interface over a
// null instance, used only for the `canEdit` capability query.
#[Swag.NoDoc]
struct PropertyEditorReg
{
    public
    {
        type: const *Swag.TypeInfoStruct     // Implementing type.
        itf:  IPropertyEditor                // Interface over a null instance, for `canEdit` queries.
    }
}

impl Properties
{
    // Process-wide registry of custom editors, consulted by every grid before the built-in
    // editors. Mirrors Image.decoders / Image.encoders.
    internal var editors: Array'PropertyEditorReg

    // Registers the editor type `T`, which must implement [[Gui.IPropertyEditor]], for every grid.
    //
    // Call it once, typically from a `#init` block. A later registration takes precedence over an
    // earlier one for the same field type, which is how a custom editor replaces a built-in one.
    //
    // The body is kept to `#typeof` and `Swag.makeInterface`, and delegates the registry mutation
    // to the non-generic `addEditor`: this generic is instantiated in the caller's module, which
    // cannot see the module-internal `editors` static — `addEditor`, compiled here, can.
    func(T) registerEditor()
    {
        #assert(Reflection.hasInterface(#typeof(T), IPropertyEditor))
        Properties.addEditor(#typeof(T), Swag.makeInterface(null, #typeof(T), IPropertyEditor))
    }

    // Appends a registry entry.
    //
    // It is public only so the generic `registerEditor` can call it from any module; the `editors`
    // static itself stays module-internal.
    #[Swag.NoDoc]
    func addEditor(type: const *Swag.TypeInfoStruct, itf: IPropertyEditor)
    {
        editors.add(PropertyEditorReg{type, itf})
    }

    // Returns the editor that claims `type`, or null.
    //
    // The scan runs newest first, so a later registration overrides an earlier one for the same
    // type — this is what lets a user editor replace a built-in color or vector editor, which all
    // live in this one registry.
    internal func findEditor(type: typeinfo?)->*PropertyEditorReg?
    {
        for i in reversed(Properties.editors.count) where Properties.editors[i].itf.canEdit(type) do
            return &Properties.editors[i]
        return null
    }
}
