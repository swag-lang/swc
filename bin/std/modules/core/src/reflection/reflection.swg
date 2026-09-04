#global public
#global namespace Reflection

using Swag

#[ConstExpr, Inline]
{
    // Returns whether native.
    func isNative(t: typeinfo?) => t and t.kind == .Native

    // Returns whether pointer.
    func isPointer(t: typeinfo?) => t and t.kind == .Pointer

    // Returns whether enum.
    func isEnum(t: typeinfo?) => t and t.kind == .Enum

    // Returns whether struct.
    func isStruct(t: typeinfo?) => t and t.kind == .Struct

    // Returns whether static array.
    func isStaticArray(t: typeinfo?) => t and t.kind == .Array

    // Returns whether slice.
    func isSlice(t: typeinfo?) => t and t.kind == .Slice

    // Returns whether type alias.
    func isTypeAlias(t: typeinfo?) => t and t.kind == .Alias

    // Returns whether interface.
    func isInterface(t: typeinfo?) => t and t.kind == .Interface

    // Returns whether integer.
    func isInteger(t: typeinfo?) => t and t.flags & .Integer

    // Returns whether float.
    func isFloat(t: typeinfo?) => t and t.flags & .Float

    // Returns whether generic.
    func isGeneric(t: typeinfo?) => t and t.flags & .Generic

    // Returns whether tuple.
    func isTuple(t: typeinfo?) => t and t.flags & .Tuple

    // Returns whether type.
    func isType(t: typeinfo?) => t and t.flags & .PointerTypeInfo

    // Returns whether pointer ref.
    func isPointerRef(t: typeinfo?) => t and t.flags & .PointerRef

    // Returns whether pointer arithmetic.
    func isPointerArithmetic(t: typeinfo?) => t and t.flags & .PointerArithmetic

    // Returns whether the type is an enum marked with #[Swag.EnumFlags].
    func isFlagsEnum(t: typeinfo?)->bool
    {
        return isEnum(t) and hasAttribute(t, EnumFlags)
    }

    // Returns whether simple native.
    func isSimpleNative(t: typeinfo?)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t!
        return tt.nativeKind != .Any and tt.nativeKind != .String
    }

    // Returns whether rune.
    func isRune(t: typeinfo?)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t!
        return tt.nativeKind == .Rune
    }

    // Returns whether any.
    func isAny(t: typeinfo?)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t!
        return tt.nativeKind == .Any
    }

    // Returns whether bool.
    func isBool(t: typeinfo?)->bool
    {
        if !isNative(t) do
            return false

        let tt = cast(const *TypeInfoNative) t!
        return tt.nativeKind == .Bool
    }

    // Returns whether string.
    func isString(t: typeinfo?)->bool
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
            result = Swag.max(result, cast(u64) type.sizeof)
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
    func assign(destination: *void?, source: const *void?, type: typeinfo?)
    {
        if !destination or !source or !type or destination == source do
            return

        if !canCopy(type)
        {
            Swag.panic("Reflection.assign cannot copy this type", #curlocation)
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
    func reset(destination: *void?, type: typeinfo?)
    {
        if !destination or !type
        {
            Swag.panic("Reflection.reset cannot reset a null type", #curlocation)
            return
        }

        let nnDst  = destination
        let nnType = type
        if !Memory.canDefaultInit(nnType)
        {
            Swag.panic("Reflection.reset cannot default-initialize this type", #curlocation)
            return
        }

        Memory.dropType(nnDst, nnType)
        Memory.defaultInit(nnDst, nnType)
    }
}

private var g_HashCrcToType:  HashTable'(u32, typeinfo)
private var g_HashNameToType: HashTable'(string, typeinfo)
private var g_HashKeyToType:  HashTable'(string, typeinfo?)
private var g_HashLock:       Sync.RWLock

private func addCrcTypeIdentity(crc: u32, type: typeinfo?)
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

private func registerStableTypeKeyNoLock(type: typeinfo)
{
    if type.kind != .Struct do
        return

    let key = attributeValue(type, Serialization.TypeKey, "name")
    if key == null do
        return

    let stableKey = cast(string) key!
    let existing  = g_HashKeyToType.tryFind(stableKey)
    if !existing
    {
        g_HashKeyToType.add(stableKey, type)
        return
    }

    // Reflection can expose the same logical type through distinct module-local
    // descriptors. Prefer the descriptor registered most recently so an interface's
    // runtime itable and the serialization registry agree by pointer identity.
    if existing.value and existing.value!.fullname == type.fullname
    {
        g_HashKeyToType.add(stableKey, type)
        return
    }

    // Null is sticky: it records that two distinct logical types declared this key.
    g_HashKeyToType.add(stableKey, null)
}

private func registerTypeNoLock(type: typeinfo?)->bool
{
    if !type do
        return false

    // Do this before the graph's visited check. A type can first be reached through an
    // imported descriptor without attributes, then explicitly registered through its
    // defining module where TypeKey is available.
    registerStableTypeKeyNoLock(type)

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
        addCrcTypeIdentity(Hash.Crc32.compute(type.fullname), type)
    if type.name != null and type.name != "" do
        addCrcTypeIdentity(Hash.Crc32.compute(type.name), type)

    return true
}

private func registerTypeGraphNoLock(type: typeinfo?)
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

    for m in Swag.processInfos().modules
    {
        for t in m.types
        {
            registerTypeGraphNoLock(t)
        }
    }
}

// Returns the registered type associated with a CRC, or null.
func typeFromCrc(crc: u32)->typeinfo?
{
    Sync.sharedLock(&g_HashLock)
    let e = g_HashCrcToType.tryFind(crc)
    if !e do
        return null
    return e.value
}

// Returns the registered type associated with a name, or null.
func typeFromName(name: string)->typeinfo?
{
    Sync.sharedLock(&g_HashLock)
    let e = g_HashNameToType.tryFind(name)
    if !e do
        return null
    return e.value
}

// Returns the registered struct associated with a stable serialization key.
//
// Returns null when the key is unknown or declared by more than one struct.
internal func typeFromKey(key: string)->typeinfo?
{
    Sync.sharedLock(&g_HashLock)
    let e = g_HashKeyToType.tryFind(key)
    if !e do
        return null
    return e.value
}
