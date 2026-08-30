#global private

// Runtime struct field iteration: walk fields by index, check name/type/offset.

struct Color
{
    r: u8
    g: u8
    b: u8
    a: u8
}

struct Rect
{
    x: f32
    y: f32
    w: f32
    h: f32
}

struct Node
{
    name:  string
    value: s32
    flag:  bool
}

// Iterate struct fields at runtime, summing offsets.
#test
{
    let info = cast(const *Swag.TypeInfoStruct) #typeof(Color)
    Swag.assert(info.fields.count == 4)

    var offsetSum: u32 = 0
    for i in info.fields.count do
        offsetSum += cast(u32) info.fields[i].offset

    // offsets: 0, 1, 2, 3
    Swag.assert(offsetSum == 6)
}

// Check field names at runtime.
#test
{
    let info = cast(const *Swag.TypeInfoStruct) #typeof(Rect)
    Swag.assert(info.fields[0].name == "x")
    Swag.assert(info.fields[1].name == "y")
    Swag.assert(info.fields[2].name == "w")
    Swag.assert(info.fields[3].name == "h")
}

// Check field types at runtime.
#test
{
    let info = cast(const *Swag.TypeInfoStruct) #typeof(Node)
    Swag.assert(info.fields.count == 3)
    Swag.assert(info.fields[0].pointedType == string)
    Swag.assert(info.fields[1].pointedType == s32)
    Swag.assert(info.fields[2].pointedType == bool)
}

// Field count and names for single-field struct.
struct Single { only: f64 }

// Single-field struct reflection
#test
{
    let info = cast(const *Swag.TypeInfoStruct) #typeof(Single)
    Swag.assert(info.fields.count == 1)
    Swag.assert(info.fields[0].name == "only")
    Swag.assert(info.fields[0].pointedType == f64)
}

// Enum type info: iterate values at runtime.
enum Status: u8
{
    Idle
    Running
    Done
}

#test
{
    let info = cast(const *Swag.TypeInfoEnum) #typeof(Status)
    Swag.assert(info.rawType == u8)
    Swag.assert(info.values.count == 3)
    Swag.assert(info.values[0].name == "Idle")
    Swag.assert(info.values[1].name == "Running")
    Swag.assert(info.values[2].name == "Done")
}

// Verify sizeof through reflection matches #sizeof.
#test
{
    let colorInfo = cast(const *Swag.TypeInfo) #typeof(Color)
    let rectInfo  = cast(const *Swag.TypeInfo) #typeof(Rect)
    Swag.assert(colorInfo.sizeof == #sizeof(Color))
    Swag.assert(rectInfo.sizeof == #sizeof(Rect))
}
