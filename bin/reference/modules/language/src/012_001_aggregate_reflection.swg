#global private

/**
# Struct and Enum Reflection

Every 'typeinfo' begins with 'Swag.TypeInfo'. Use an 'is' pattern to borrow a
specialized descriptor in a branch, or 'assume cast' when its type is known. A struct descriptor exposes layout, fields,
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
    Swag.require(base.kind == .Struct)

    let type   = assume cast(const *Swag.TypeInfoStruct, base)
    let fields = unwrap type.fields

    Swag.require(type.structName == "ReflectedPoint")
    Swag.require(type.sizeof == #sizeof(ReflectedPoint))
    Swag.require(fields.count == 2)
    Swag.require(fields[0].name == "x")
    Swag.require(fields[0].pointedType == s32)
    Swag.require(fields[0].offset == #offsetof(ReflectedPoint.x))
    Swag.require(fields[1].name == "y")
    Swag.require(fields[1].offset == #offsetof(ReflectedPoint.y))

    let methods = unwrap type.methods
    Swag.require(methods.count == 1)
    Swag.require(methods[0].name == "sum")
    Swag.require(methods[0].pointedType!.kind == .Func)
}

/**
An enum descriptor reports the storage type and one 'TypeValue' per named
value. 'TypeValue.value' is an untyped pointer to the exported constant; use a
typed reflection helper before reading it in general-purpose code.
*/

#test
{
    let base = #typeof(ReflectedState)
    Swag.require(base.kind == .Enum)

    let type   = assume cast(const *Swag.TypeInfoEnum, base)
    let values = unwrap type.values

    Swag.require(type.rawType == u8)
    Swag.require(values.count == 3)
    Swag.require(values[0].name == "Idle")
    Swag.require(values[1].name == "Running")
    Swag.require(values[2].name == "Done")
    Swag.require(values[0].pointedType == ReflectedState)
}

/**
Reflection describes declarations; it does not bypass visibility, constness, or
ownership. When writing a generic serializer or editor, check the descriptor with an 'is' pattern, check
nullable descriptor slices, and derive field addresses from a live instance
plus 'TypeValue.offset'.
*/

func reflectedFieldCount(type: typeinfo)->u64
{
    if type is Swag.TypeInfoStruct as info do
        return info.fields.count
    return 0
}

#test
{
    Swag.require(reflectedFieldCount(ReflectedPoint) == 2)
    Swag.require(reflectedFieldCount(s32) == 0)
}
