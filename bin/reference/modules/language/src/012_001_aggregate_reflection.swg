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
    @assert(base.kind == .Struct)

    let type   = cast(const *Swag.TypeInfoStruct) base
    let fields = type.fields!

    @assert(type.structName == "ReflectedPoint")
    @assert(type.sizeof == #sizeof(ReflectedPoint))
    @assert(@countof(fields) == 2)
    @assert(fields[0].name == "x")
    @assert(fields[0].pointedType == s32)
    @assert(fields[0].offset == #offsetof(ReflectedPoint.x))
    @assert(fields[1].name == "y")
    @assert(fields[1].offset == #offsetof(ReflectedPoint.y))

    let methods = type.methods!
    @assert(@countof(methods) == 1)
    @assert(methods[0].name == "sum")
    @assert(methods[0].pointedType!.kind == .Func)
}

/**
An enum descriptor reports the storage type and one 'TypeValue' per named
value. 'TypeValue.value' is an untyped pointer to the exported constant; use a
typed reflection helper before reading it in general-purpose code.
*/

#test
{
    let base = #typeof(ReflectedState)
    @assert(base.kind == .Enum)

    let type   = cast(const *Swag.TypeInfoEnum) base
    let values = type.values!

    @assert(type.rawType == u8)
    @assert(@countof(values) == 3)
    @assert(values[0].name == "Idle")
    @assert(values[1].name == "Running")
    @assert(values[2].name == "Done")
    @assert(values[0].pointedType == ReflectedState)
}

/**
Reflection describes declarations; it does not bypass visibility, constness, or
ownership. When writing a generic serializer or editor, validate 'kind', check
nullable descriptor slices, and derive field addresses from a live instance
plus 'TypeValue.offset'.
*/
