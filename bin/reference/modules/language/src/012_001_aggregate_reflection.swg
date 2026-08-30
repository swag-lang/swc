#global private

/**
# Struct and Enum Reflection

Every 'typeinfo' begins with 'Swag.TypeInfo'. Inspect its 'kind' before casting
to a specialized descriptor. A struct descriptor exposes layout, fields,
interfaces, lifecycle hooks, generic arguments, and any methods requested with
'Swag.ExportType'.
*/

#[Swag.ExportType(.Methods)]
struct ReflectedPoint
{
    x: s32
    y: s32
}

impl ReflectedPoint
{
    mtd sum()->s32 => .x + .y
}

enum ReflectedState: u8
{
    Idle
    Running
    Done
}

#test
{
    let base = #typeof(ReflectedPoint)
    Swag.assert(base.kind == .Struct)

    let type   = cast(const *Swag.TypeInfoStruct) base
    let fields = type.fields!

    Swag.assert(type.structName == "ReflectedPoint")
    Swag.assert(type.sizeof == #sizeof(ReflectedPoint))
    Swag.assert(fields.count == 2)
    Swag.assert(fields[0].name == "x")
    Swag.assert(fields[0].pointedType == s32)
    Swag.assert(fields[0].offset == #offsetof(ReflectedPoint.x))
    Swag.assert(fields[1].name == "y")
    Swag.assert(fields[1].offset == #offsetof(ReflectedPoint.y))

    let methods = type.methods!
    Swag.assert(methods.count == 1)
    Swag.assert(methods[0].name == "sum")
    Swag.assert(methods[0].pointedType!.kind == .Func)
}

/**
An enum descriptor reports the storage type and one 'TypeValue' per named
value. 'TypeValue.value' is an untyped pointer to the exported constant; use a
typed reflection helper before reading it in general-purpose code.
*/

#test
{
    let base = #typeof(ReflectedState)
    Swag.assert(base.kind == .Enum)

    let type   = cast(const *Swag.TypeInfoEnum) base
    let values = type.values!

    Swag.assert(type.rawType == u8)
    Swag.assert(values.count == 3)
    Swag.assert(values[0].name == "Idle")
    Swag.assert(values[1].name == "Running")
    Swag.assert(values[2].name == "Done")
    Swag.assert(values[0].pointedType == ReflectedState)
}

/**
Reflection describes declarations; it does not bypass visibility, constness, or
ownership. When writing a generic serializer or editor, validate 'kind', check
nullable descriptor slices, and derive field addresses from a live instance
plus 'TypeValue.offset'.
*/
