#global public
#global namespace Reflection

using Swag

#[ConstExpr, Inline]
{
    // Returns whether native.
    func isNative(t: #null typeinfo) => t and t.kind == .Native

    // Returns whether pointer.
    func isPointer(t: typeinfo) => t and t.kind == .Pointer

    // Returns whether enum.
    func isEnum(t: #null typeinfo) => t and t.kind == .Enum

    // Returns whether struct.
    func isStruct(t: #null typeinfo) => t and t.kind == .Struct

    // Returns whether static array.
    func isStaticArray(t: #null typeinfo) => t and t.kind == .Array

    // Returns whether slice.
    func isSlice(t: typeinfo) => t and t.kind == .Slice

    // Returns whether type alias.
    func isTypeAlias(t: #null typeinfo) => t and t.kind == .Alias

    // Returns whether interface.
    func isInterface(t: typeinfo) => t and t.kind == .Interface

    // Returns whether integer.
    func isInteger(t: #null typeinfo) => t and t.flags & .Integer

    // Returns whether float.
    func isFloat(t: #null typeinfo) => t and t.flags & .Float

    // Returns whether generic.
    func isGeneric(t: #null typeinfo) => t and t.flags & .Generic

    // Returns whether tuple.
    func isTuple(t: typeinfo) => t and t.flags & .Tuple

    // Returns whether type.
    func isType(t: typeinfo) => t and t.flags & .PointerTypeInfo

    // Returns whether pointer ref.
    func isPointerRef(t: typeinfo) => t and t.flags & .PointerRef

    // Returns whether pointer arithmetic.
    func isPointerArithmetic(t: typeinfo) => t and t.flags & .PointerArithmetic

    // Returns whether the type is an enum marked with #[Swag.EnumFlags].
    func isFlagsEnum(t: #null typeinfo)->bool
    {
        return isEnum(t) and hasAttribute(t, EnumFlags)
    }

    // Returns whether simple native.
    func isSimpleNative(t: #null typeinfo)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t!
        return tt.nativeKind != .Any and tt.nativeKind != .String
    }

    // Returns whether rune.
    func isRune(t: #null typeinfo)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t!
        return tt.nativeKind == .Rune
    }

    // Returns whether any.
    func isAny(t: typeinfo)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t!
        return tt.nativeKind == .Any
    }

    // Returns whether bool.
    func isBool(t: #null typeinfo)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t!
        return tt.nativeKind == .Bool
    }

    // Returns whether string.
    func isString(t: #null typeinfo)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t!
        return tt.nativeKind == .String
    }
}

#[ConstExpr]
{
    // Resolves nested aliases and returns their underlying type.
    func resolveAliases(type: typeinfo)->typeinfo
    {
        var result = type
        while isTypeAlias(result)
        {
            let typeAlias = cast(const *TypeInfoAlias) result
            result = typeAlias.rawType
        }

        return result
    }

    // Returns the largest size among the supplied types.
    func maximumSize(types: const [..] typeinfo)->u64
    {
        var result = 0'u64
        for type in types do
            result = @max(result, cast(u64) type.sizeof)
        return result
    }

    // Returns the union of the flags carried by the supplied types.
    func combinedFlags(types: const [..] typeinfo)->Swag.TypeInfoFlags
    {
        var result: Swag.TypeInfoFlags = .Zero
        for type in types do
            result |= type.flags
        return result
    }

    // Assigns a runtime-typed value, preserving its copy and drop semantics.
    func assign(destination: #null *void, source: #null const *void, type: #null typeinfo)
    {
        if !destination or !source or !type or destination == source do
            return

        if !canCopy(type)
        {
            @panic("Reflection.assign cannot copy this type", #curlocation)
            return
        }

        let nnDst  = destination
        let nnSrc  = source
        let nnType = type
        Memory.dropType(nnDst, nnType)
        Memory.copy(nnDst, nnSrc, cast(u64) nnType.sizeof)
        Memory.postCopyType(nnDst, nnType)
    }

    // Resets a runtime-typed value to its declared default value.
    func reset(destination: #null *void, type: #null typeinfo)
    {
        if !destination or !type
        {
            @panic("Reflection.reset cannot reset a null type", #curlocation)
            return
        }

        let nnDst  = destination
        let nnType = type
        if !Memory.canDefaultInit(nnType)
        {
            @panic("Reflection.reset cannot default-initialize this type", #curlocation)
            return
        }

        Memory.dropType(nnDst, nnType)
        Memory.defaultInit(nnDst, nnType)
    }
}

private var g_HashCrcToType: HashTable'(u32, typeinfo)
private var g_HashNameToType: HashTable'(string, typeinfo)
private var g_HashLock: Sync.RWLock

private func typeValueCrc(val: Swag.TypeValue)->u32
{
    if val.crc do
        return val.crc
    if val.name == null do
        return 0
    return Hash.Crc32.compute(val.name)
}

private func addCrcToTypeAlias(crc: u32, type: #null typeinfo)
{
    if !crc or !type do
        return

    let existing = g_HashCrcToType.tryFind(crc)
    if existing
    {
        // The same logical type registers again from another module; anything else is
        // two types colliding on one crc, which would resolve unpredictably.
        Debug.assert(existing.value.fullname == type.fullname, "type crc collision")
        return
    }

    g_HashCrcToType.add(crc, type)
}

private func registerTypeNoLock(type: #null typeinfo)->bool
{
    if !type do
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

    // A struct can declare the names it had in older streams; registering their crcs
    // makes a stream written under an old name resolve to the renamed type.
    if type.kind == .Struct
    {
        let aliases = attributes(type, Serialization.Alias)
        for al in aliases
        {
            let value = attributeValue(al, "name")
            if value != null do
                addCrcToTypeAlias(Hash.Crc32.compute(cast(string) value!), type)
        }
    }

    return true
}

private func registerTypeGraphNoLock(type: #null typeinfo)
{
    if !registerTypeNoLock(type) do
        return

    let nnType = type!
    switch nnType.kind
    {
    case .Alias:
        let typeAlias = cast(const *TypeInfoAlias) nnType
        registerTypeGraphNoLock(typeAlias.rawType)

    case .Array:
        let typeArray = cast(const *TypeInfoArray) nnType
        registerTypeGraphNoLock(typeArray.pointedType)

    case .Enum:
        let typeEnum = cast(const *TypeInfoEnum) nnType
        registerTypeGraphNoLock(typeEnum.rawType)

    case .Pointer:
        let typePointer = cast(const *TypeInfoPointer) nnType
        registerTypeGraphNoLock(typePointer.pointedType)

    case .Slice:
        let typeSlice = cast(const *TypeInfoSlice) nnType
        registerTypeGraphNoLock(typeSlice.pointedType)

    case .Struct:
        let typeStruct = cast(const *TypeInfoStruct) nnType
        for &field in typeStruct.fields do
            registerTypeGraphNoLock(field.pointedType)
        for &generic in typeStruct.generics do
            registerTypeGraphNoLock(generic.pointedType)
    }
}

// Registers a type and every type reachable from its reflected graph.
func registerType(type: typeinfo)
{
    Sync.scopedLock(&g_HashLock)
    registerTypeGraphNoLock(type)
}

// Registers an additional CRC alias for a type.
func registerTypeAlias(crc: u32, type: typeinfo)
{
    Sync.scopedLock(&g_HashLock)
    addCrcToTypeAlias(crc, type)
}

// Infers an interface implementation from the CRCs of its serialized fields.
// Returns null when no unique best match exists.
func inferInterfaceImplementation(itf: typeinfo, fieldCrcs: const [..] u32)->#null typeinfo
{
    var bestType:  #null typeinfo
    var bestScore: u64
    var ambiguous: bool

    Sync.sharedLock(&g_HashLock)
    for ignoredCrc, [t] in g_HashCrcToType
    {
        if !hasInterface(t, itf) do
            continue

        let typeStruct = cast(const *TypeInfoStruct) t!
        var score      = 0'u64
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

// Returns the registered type associated with a CRC, or null.
func typeFromCrc(crc: u32)->#null typeinfo
{
    Sync.sharedLock(&g_HashLock)
    let e = g_HashCrcToType.tryFind(crc)
    if !e do
        return null
    return e.value
}

// Returns the registered type associated with a name, or null.
func typeFromName(name: string)->#null typeinfo
{
    Sync.sharedLock(&g_HashLock)
    let e = g_HashNameToType.tryFind(name)
    if !e do
        return null
    return e.value
}
