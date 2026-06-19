#global fileprivate

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
    @assert(@countof(info.fields) == 4)

    var offsetSum: u32 = 0
    for i in @countof(info.fields) do
        offsetSum += cast(u32) info.fields[i].offset

    // offsets: 0, 1, 2, 3
    @assert(offsetSum == 6)
}

// Check field names at runtime.
#test
{
    let info = cast(const *Swag.TypeInfoStruct) #typeof(Rect)
    @assert(info.fields[0].name == "x")
    @assert(info.fields[1].name == "y")
    @assert(info.fields[2].name == "w")
    @assert(info.fields[3].name == "h")
}

// Check field types at runtime.
#test
{
    let info = cast(const *Swag.TypeInfoStruct) #typeof(Node)
    @assert(@countof(info.fields) == 3)
    @assert(info.fields[0].pointedType == string)
    @assert(info.fields[1].pointedType == s32)
    @assert(info.fields[2].pointedType == bool)
}

// Field count and names for single-field struct.
struct Single { only: f64 }

// Single-field struct reflection
#test
{
    let info = cast(const *Swag.TypeInfoStruct) #typeof(Single)
    @assert(@countof(info.fields) == 1)
    @assert(info.fields[0].name == "only")
    @assert(info.fields[0].pointedType == f64)
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
    @assert(info.rawType == u8)
    @assert(@countof(info.values) == 3)
    @assert(info.values[0].name == "Idle")
    @assert(info.values[1].name == "Running")
    @assert(info.values[2].name == "Done")
}

// Verify sizeof through reflection matches #sizeof.
#test
{
    let colorInfo = cast(const *Swag.TypeInfo) #typeof(Color)
    let rectInfo  = cast(const *Swag.TypeInfo) #typeof(Rect)
    @assert(colorInfo.sizeof == #sizeof(Color))
    @assert(rectInfo.sizeof == #sizeof(Rect))
}
