#global public
#global namespace Reflection
using Swag

#[ConstExpr, Inline]
{
    func isNative(t: typeinfo)      => t.kind == .Native
    func isPointer(t: typeinfo)     => t.kind == .Pointer
    func isEnum(t: typeinfo)        => t.kind == .Enum
    func isStruct(t: typeinfo)      => t.kind == .Struct
    func isStaticArray(t: typeinfo) => t.kind == .Array
    func isSlice(t: typeinfo)       => t.kind == .Slice
    func isTypeAlias(t: typeinfo)   => t.kind == .Alias
    func isInterface(t: typeinfo)   => t.kind == .Interface

    func isInteger(t: typeinfo)           => t.flags & .Integer
    func isFloat(t: typeinfo)             => t.flags & .Float
    func isGeneric(t: typeinfo)           => t.flags & .Generic
    func isTuple(t: typeinfo)             => t.flags & .Tuple
    func isType(t: typeinfo)              => t.flags & .PointerTypeInfo
    func isPointerRef(t: typeinfo)        => t.flags & .PointerRef
    func isPointerArithmetic(t: typeinfo) => t.flags & .PointerArithmetic

    func isEnumFlags(t: typeinfo)->bool
    {
        return isEnum(t)
    }

    func isSimpleNative(t: typeinfo)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t
        return tt.nativeKind != .Any and tt.nativeKind != .String
    }

    func isRune(t: typeinfo)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t
        return tt.nativeKind == .Rune
    }

    func isAny(t: typeinfo)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t
        return tt.nativeKind == .Any
    }

    func isBool(t: typeinfo)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t
        return tt.nativeKind == .Bool
    }

    func isString(t: typeinfo)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t
        return tt.nativeKind == .String
    }
}

#[ConstExpr]
{
    // In case this is a type alias, need to go deep inside it to find the right type
    func makeConcreteAlias(type: typeinfo)->typeinfo
    {
        var result = type
        while isTypeAlias(result)
        {
            let typeAlias = cast(const *TypeInfoAlias) result
            result = typeAlias.rawType
        }

        return result
    }

    // Returns the maximum sizeof a bunch of 'typeinfo'
    func maxSizeOf(v: const [..] typeinfo)->u64
    {
        var res = 0'u32
        for p in v do
            res = @max(res, p.sizeof)
        return res
    }

    // Make an union of flags of all types
    func orFlags(v: const [..] typeinfo)->Swag.TypeInfoFlags
    {
        var res: Swag.TypeInfoFlags = .Zero
        for p in v do
            res |= p.flags
        return res
    }

    func copy(dst, src: *void, type: typeinfo)
    {
        Memory.copy(dst, src, cast(u64) type.sizeof)
        Memory.postCopyType(dst, type)
    }

    func reset(dst: *void, type: typeinfo)
    {
        if !Memory.canDefaultInit(type)
        {
            @panic("Reflection.reset cannot default-initialize this type", #curlocation)
            return
        }
        Memory.dropType(dst, type)
        Memory.defaultInit(dst, type)
    }
}

private var g_HashCrcToType: HashTable'(u32, typeinfo)
private var g_HashNameToType: HashTable'(string, typeinfo)
private var g_HashLock: Sync.RWLock

private func typeValueCrc(val: Swag.TypeValue)->u32
{
    if val.crc do
        return val.crc
    return Hash.Crc32.compute(val.name)
}

private func addCrcToTypeAlias(crc: u32, type: typeinfo)
{
    if !crc or g_HashCrcToType.contains(crc) do
        return
    g_HashCrcToType.add(crc, type)
}

private func registerTypeNoLock(type: typeinfo)->bool
{
    if type == null do
        return false

    if type.crc and g_HashCrcToType.contains(type.crc) do
        return false
    if !type.crc
    {
        if type.fullname != null and type.fullname != "" and g_HashNameToType.contains(type.fullname) do
            return false
        if (type.fullname == null or type.fullname == "") and type.name != null and type.name != "" and g_HashNameToType.contains(type.name) do
            return false
    }

    if type.crc do
        g_HashCrcToType.add(type.crc, type)

    if type.fullname != null and type.fullname != "" and !g_HashNameToType.contains(type.fullname) do
        g_HashNameToType.add(type.fullname, type)
    elif (type.fullname == null or type.fullname == "") and type.name != null and type.name != "" and !g_HashNameToType.contains(type.name) do
        g_HashNameToType.add(type.name, type)

    if type.fullname != null and type.fullname != "" do
        addCrcToTypeAlias(Hash.Crc32.compute(type.fullname), type)
    if type.name != null and type.name != "" do
        addCrcToTypeAlias(Hash.Crc32.compute(type.name), type)

    return true
}

private func registerTypeGraphNoLock(type: typeinfo)
{
    if !registerTypeNoLock(type) do
        return

    switch type.kind
    {
    case .Alias:
        let typeAlias = cast(const *TypeInfoAlias) type
        registerTypeGraphNoLock(typeAlias.rawType)
    case .Array:
        let typeArray = cast(const *TypeInfoArray) type
        registerTypeGraphNoLock(typeArray.pointedType)
    case .Enum:
        let typeEnum = cast(const *TypeInfoEnum) type
        registerTypeGraphNoLock(typeEnum.rawType)
    case .Pointer:
        let typePointer = cast(const *TypeInfoPointer) type
        registerTypeGraphNoLock(typePointer.pointedType)
    case .Slice:
        let typeSlice = cast(const *TypeInfoSlice) type
        registerTypeGraphNoLock(typeSlice.pointedType)
    case .Struct:
        let typeStruct = cast(const *TypeInfoStruct) type
        for &field in typeStruct.fields do
            registerTypeGraphNoLock(field.pointedType)
        for &generic in typeStruct.generics do
            registerTypeGraphNoLock(generic.pointedType)
    }
}

func registerType(type: typeinfo)
{
    Sync.scopedLock(&g_HashLock)
    registerTypeGraphNoLock(type)
}

func registerCrcToTypeAlias(crc: u32, type: typeinfo)
{
    Sync.scopedLock(&g_HashLock)
    addCrcToTypeAlias(crc, type)
}

func inferTypeWithInterfaceFields(itf: typeinfo, fieldCrcs: const [..] u32)->#null typeinfo
{
    var bestType:  typeinfo
    var bestScore: u64
    var ambiguous: bool

    Sync.sharedLock(&g_HashLock)
    for ignoredCrc, t in g_HashCrcToType
    {
        if !hasInterface(t, itf) do
            continue

        let typeStruct = cast(const *TypeInfoStruct) t
        var score = 0'u64
        for streamCrc in fieldCrcs
        {
            for &field in typeStruct.fields
            {
                if typeValueCrc(field) == streamCrc
                {
                    score += 1
                    break
                }
            }
        }

        if score == 0 do
            continue

        if score > bestScore
        {
            bestType  = t
            bestScore = score
            ambiguous = false
        }
        elif score == bestScore and t != bestType do
            ambiguous = true
    }

    if ambiguous do
        return null
    return bestType
}

// #premain can be called more than once if we compile/run more than one
// module using Core at the same time. So lock !
#premain
{
    Sync.scopedLock(&g_HashLock)

    registerTypeGraphNoLock(#typeof(bool))
    registerTypeGraphNoLock(#typeof(u8))
    registerTypeGraphNoLock(#typeof(u16))
    registerTypeGraphNoLock(#typeof(u32))
    registerTypeGraphNoLock(#typeof(u64))
    registerTypeGraphNoLock(#typeof(s8))
    registerTypeGraphNoLock(#typeof(s16))
    registerTypeGraphNoLock(#typeof(s32))
    registerTypeGraphNoLock(#typeof(s64))
    registerTypeGraphNoLock(#typeof(f32))
    registerTypeGraphNoLock(#typeof(f64))
    registerTypeGraphNoLock(#typeof(rune))

    for m in @pinfos.modules
    {
        for t in m.types
        {
            registerTypeGraphNoLock(t)
        }
    }
}

// Convert a crc to a registered typeinfo
func crcToType(crc: u32)->#null typeinfo
{
    Sync.sharedLock(&g_HashLock)
    let e = g_HashCrcToType.tryFind(crc)
    if !e do
        return null
    return e.value
}

// Convert a crc to a registered typeinfo
func nameToType(name: string)->#null typeinfo
{
    Sync.sharedLock(&g_HashLock)
    let e = g_HashNameToType.tryFind(name)
    if !e do
        return null
    return e.value
}
