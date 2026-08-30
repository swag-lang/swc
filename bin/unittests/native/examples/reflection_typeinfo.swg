#global private

// Reflection-driven struct "serializer": iterate struct fields at compile-time
// and runtime to compute checksums, validate field counts, and build
// descriptive metadata without hand-written per-field code.

struct Config
{
    width:  s32
    height: s32
    depth:  s32
    flags:  u32
}

struct Vertex
{
    x: f32
    y: f32
    z: f32
}

struct Metadata
{
    id:    u64
    tag:   s32
    valid: bool
}

// Compile-time field count checks.
#assert(((cast(const *Swag.TypeInfoStruct) #typeof(Config)).fields).count == 4)
#assert(((cast(const *Swag.TypeInfoStruct) #typeof(Vertex)).fields).count == 3)
#assert(((cast(const *Swag.TypeInfoStruct) #typeof(Metadata)).fields).count == 3)

// Compute a simple checksum over s32 fields of Config by reading field
// offsets from typeinfo and accessing memory through a raw pointer.
func checksumConfig(cfg: Config)->s32
{
    let info     = cast(const *Swag.TypeInfoStruct) #typeof(Config)
    let base     = cast(const [*] u8) &cfg
    var sum: s32 = 0
    for i in info.fields.count
    {
        let field = info.fields[i]
        if field.pointedType == s32
        {
            let ptr = cast(const *s32) (base + field.offset)
            sum += ptr[]
        }
    }
    return sum
}

#test
{
    let cfg: Config = {width: 10, height: 20, depth: 30, flags: 0xFF}
    Swag.assert(checksumConfig(cfg) == 60)
}

#test
{
    let cfg: Config = {width: -5, height: 100, depth: 0, flags: 42}
    Swag.assert(checksumConfig(cfg) == 95)
}

// Count how many fields of a given type a struct has (runtime).
func countFieldsOfType(info: const *Swag.TypeInfoStruct, target: const *Swag.TypeInfo)->s32
{
    var n: s32 = 0
    let fields = info.fields!
    for i in fields.count
    {
        if fields[i].pointedType == target do
            n += 1
    }
    return n
}

#test
{
    let configInfo = cast(const *Swag.TypeInfoStruct) #typeof(Config)
    let vertexInfo = cast(const *Swag.TypeInfoStruct) #typeof(Vertex)
    let metaInfo   = cast(const *Swag.TypeInfoStruct) #typeof(Metadata)

    Swag.assert(countFieldsOfType(configInfo, #typeof(s32)) == 3)
    Swag.assert(countFieldsOfType(configInfo, #typeof(u32)) == 1)
    Swag.assert(countFieldsOfType(vertexInfo, #typeof(f32)) == 3)
    Swag.assert(countFieldsOfType(metaInfo, #typeof(u64)) == 1)
    Swag.assert(countFieldsOfType(metaInfo, #typeof(bool)) == 1)
}

// Build a "schema fingerprint" from field names: sum of first chars.
func nameFingerprint(info: const *Swag.TypeInfoStruct)->s32
{
    var fp: s32 = 0
    let fields  = info.fields!
    for i in fields.count
    {
        let name = fields[i].name
        if name.count > 0 do
            fp += cast(s32) name![0]
    }
    return fp
}

#test
{
    let configInfo = cast(const *Swag.TypeInfoStruct) #typeof(Config)
    // 'w'=119, 'h'=104, 'd'=100, 'f'=102 -> 425
    Swag.assert(nameFingerprint(configInfo) == 425)
}

#test
{
    let vertexInfo = cast(const *Swag.TypeInfoStruct) #typeof(Vertex)
    // 'x'=120, 'y'=121, 'z'=122 -> 363
    Swag.assert(nameFingerprint(vertexInfo) == 363)
}

// Verify total sizeof through reflection matches sum of known field sizes.
#test
{
    let info = cast(const *Swag.TypeInfoStruct) #typeof(Vertex)
    Swag.assert(info.sizeof == #sizeof(Vertex))
    Swag.assert(info.sizeof == 12)
}

// Enum value reflection: build a tag->name lookup.
enum LogLevel: u8
{
    Trace
    Debug
    Info
    Warn
    Error
}

func levelName(level: LogLevel)->string
{
    let info = cast(const *Swag.TypeInfoEnum) #typeof(LogLevel)
    for i in info.values.count
    {
        let stored = cast(const *LogLevel) info.values[i].value!
        if stored[] == level do
            return info.values[i].name!
    }
    return "unknown"
}

#test
{
    Swag.assert(levelName(.Trace) == "Trace")
    Swag.assert(levelName(.Info) == "Info")
    Swag.assert(levelName(.Error) == "Error")
}

// Count enum values at runtime.
#test
{
    let info = cast(const *Swag.TypeInfoEnum) #typeof(LogLevel)
    Swag.assert(info.values.count == 5)
    Swag.assert(info.rawType == u8)
}
