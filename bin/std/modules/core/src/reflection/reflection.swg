#global public
#global namespace Reflection

using Swag

#[ConstExpr, Inline]
{
    // Returns whether `t` is a native type, such as an integer, a float, a `bool`, a `string`, or `any`.
    func isNative(t: typeinfo?) => t and t.kind == .Native

    // Returns whether `t` is a pointer type.
    func isPointer(t: typeinfo?) => t and t.kind == .Pointer

    // Returns whether `t` is an enum type.
    func isEnum(t: typeinfo?) => t and t.kind == .Enum

    // Returns whether `t` is a struct type.
    func isStruct(t: typeinfo?) => t and t.kind == .Struct

    // Returns whether `t` is a static array type.
    func isStaticArray(t: typeinfo?) => t and t.kind == .Array

    // Returns whether `t` is a slice type.
    func isSlice(t: typeinfo?) => t and t.kind == .Slice

    // Returns whether `t` is a type alias.
    func isTypeAlias(t: typeinfo?) => t and t.kind == .Alias

    // Returns whether `t` is an interface type.
    func isInterface(t: typeinfo?) => t and t.kind == .Interface

    // Returns whether `t` is a native integer type.
    func isInteger(t: typeinfo?) => t and t.flags & .Integer

    // Returns whether `t` is a native floating-point type.
    func isFloat(t: typeinfo?) => t and t.flags & .Float

    // Returns whether `t` is a generic type.
    func isGeneric(t: typeinfo?) => t and t.flags & .Generic

    // Returns whether `t` is a tuple type.
    func isTuple(t: typeinfo?) => t and t.flags & .Tuple

    // Returns whether `t` is a pointer to type information, such as `typeinfo`.
    func isType(t: typeinfo?) => t and t.flags & .PointerTypeInfo

    // Returns whether `t` is a reference type.
    func isPointerRef(t: typeinfo?) => t and t.flags & .PointerRef

    // Returns whether `t` is a block pointer that supports pointer arithmetic.
    func isPointerArithmetic(t: typeinfo?) => t and t.flags & .PointerArithmetic

    // Returns whether `t` is an enum marked with `#[Swag.EnumFlags]`.
    func isFlagsEnum(t: typeinfo?)->bool => isEnum(t) and hasAttribute(t, EnumFlags)

    // Returns whether `t` is a native type other than `any` and `string`.
    func isSimpleNative(t: typeinfo?)->bool
    {
        if not isNative(t) do
            return false

        let tt = cast #assume(const *TypeInfoNative) t!
        return tt.nativeKind != .Any and tt.nativeKind != .String
    }

    // Returns whether `t` is the native `rune` type.
    func isRune(t: typeinfo?)->bool
    {
        if not isNative(t) do
            return false

        let tt = cast #assume(const *TypeInfoNative) t!
        return tt.nativeKind == .Rune
    }

    // Returns whether `t` is the native `any` type.
    func isAny(t: typeinfo?)->bool
    {
        if not isNative(t) do
            return false

        let tt = cast #assume(const *TypeInfoNative) t!
        return tt.nativeKind == .Any
    }

    // Returns whether `t` is the native `bool` type.
    func isBool(t: typeinfo?)->bool
    {
        if not isNative(t) do
            return false

        let tt = cast #assume(const *TypeInfoNative) t!
        return tt.nativeKind == .Bool
    }

    // Returns whether `t` is the native `string` type.
    func isString(t: typeinfo?)->bool
    {
        if not isNative(t) do
            return false

        let tt = cast #assume(const *TypeInfoNative) t!
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
            let typeAlias = cast #assume(const *TypeInfoAlias) result
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

    // Copies the value of runtime type `type` at `source` over the value at `destination`.
    //
    // The previous destination value is dropped first, and the copy then runs its post-copy
    // hook. Nothing happens when a pointer or `type` is null, or when `destination` and
    // `source` are the same address. Panics when values of `type` cannot be copied.
    func assign(destination: *void?, source: const *void?, type: typeinfo?)
    {
        if not destination or not source or not type or destination == source do
            return

        if not canCopy(type)
        {
            Swag.panic("Reflection.assign cannot copy this type", #curlocation)
            return
        }

        Memory.dropType(destination, type)
        Memory.copyValueStorage(destination, source, type)
        Memory.postCopyType(destination, type)
    }

    // Resets the value of runtime type `type` at `destination` to its declared default value.
    //
    // Panics when `destination` or `type` is null, or when `type` has no default initialization.
    func reset(destination: *void?, type: typeinfo?)
    {
        if not destination or not type
        {
            Swag.panic("Reflection.reset cannot reset a null type", #curlocation)
            return
        }

        if not Memory.canDefaultInit(type)
        {
            Swag.panic("Reflection.reset cannot default-initialize this type", #curlocation)
            return
        }

        Memory.resetValueStorage(destination, type)
    }
}

private var g_HashCrcToType:  HashTable'(u32, typeinfo)
private var g_HashNameToType: HashTable'(string, typeinfo)
private var g_HashKeyToType:  HashTable'(string, typeinfo?)
private var g_HashLock:       Sync.RWLock

private func addCrcTypeIdentity(crc: u32, type: typeinfo?)
{
    if not crc or not type do
        return

    let existing = g_HashCrcToType.tryFind(crc)
    if existing
    {
        // The same logical type registers again from another module; anything else is
        // two types colliding on one crc, which would resolve unpredictably.
        Swag.assert(existing.value.fullname == type.fullname, "type crc collision")
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

    let stableKey = cast #assume (string) key
    let existing  = g_HashKeyToType.tryFind(stableKey)
    if not existing
    {
        g_HashKeyToType.add(stableKey, type)
        return
    }

    // Reflection can expose the same logical type through distinct module-local
    // descriptors. Prefer the descriptor registered most recently so an interface's
    // runtime itable and the serialization registry agree by pointer identity.
    if existing.value and existing.value.fullname == type.fullname
    {
        g_HashKeyToType.add(stableKey, type)
        return
    }

    // Null is sticky: it records that two distinct logical types declared this key.
    g_HashKeyToType.add(stableKey, null)
}

private func registerTypeNoLock(type: typeinfo?)->bool
{
    if not type do
        return false

    // Do this before the graph's visited check. A type can first be reached through an
    // imported descriptor without attributes, then explicitly registered through its
    // defining module where TypeKey is available.
    registerStableTypeKeyNoLock(type)

    if type.crc and g_HashCrcToType.contains(type.crc) do
        return false
    if not type.crc
    {
        if type.fullname != null and type.fullname != "" and g_HashNameToType.contains(type.fullname) do
            return false
        if (type.fullname == null or type.fullname == "") and type.name != null and type.name != "" and g_HashNameToType.contains(type.name) do
            return false
    }

    if type.crc do
        g_HashCrcToType.add(type.crc, type)

    if type.fullname != null and type.fullname != "" and not g_HashNameToType.contains(type.fullname) do
        g_HashNameToType.add(type.fullname, type)
    elif (type.fullname == null or type.fullname == "") and type.name != null and type.name != "" and not g_HashNameToType.contains(type.name) do
        g_HashNameToType.add(type.name, type)

    if type.fullname != null and type.fullname != "" do
        addCrcTypeIdentity(Hash.Crc32.compute(type.fullname), type)
    if type.name != null and type.name != "" do
        addCrcTypeIdentity(Hash.Crc32.compute(type.name), type)

    return true
}

private func registerTypeGraphNoLock(type: typeinfo?)
{
    if not registerTypeNoLock(type) do
        return

    let nnType = type!
    switch nnType.kind
    {
    case .Alias:
        let typeAlias = cast #assume(const *TypeInfoAlias) nnType
        registerTypeGraphNoLock(typeAlias.rawType)

    case .Array:
        let typeArray = cast #assume(const *TypeInfoArray) nnType
        registerTypeGraphNoLock(typeArray.pointedType)

    case .Enum:
        let typeEnum = cast #assume(const *TypeInfoEnum) nnType
        registerTypeGraphNoLock(typeEnum.rawType)

    case .Pointer:
        let typePointer = cast #assume(const *TypeInfoPointer) nnType
        registerTypeGraphNoLock(typePointer.pointedType)

    case .Slice:
        let typeSlice = cast #assume(const *TypeInfoSlice) nnType
        registerTypeGraphNoLock(typeSlice.pointedType)

    case .Struct:
        let typeStruct = cast #assume(const *TypeInfoStruct) nnType
        for &field in typeStruct.fields do
            registerTypeGraphNoLock(field.pointedType)
        for &generic in typeStruct.generics do
            registerTypeGraphNoLock(generic.pointedType)
    }
}

// Registers `type` and every type reachable from its reflected graph.
//
// Registered types can then be found by [[Core.Reflection.typeFromCrc]] and [[Core.Reflection.typeFromName]].
// Types exported by loaded modules are registered automatically at startup.
func registerType(type: typeinfo)
{
    Sync.scopedLock(&g_HashLock)
    registerTypeGraphNoLock(type)
}

// #premain can run more than once when several modules using Core are compiled or run at
// the same time, so registration takes the lock.
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

// Returns the registered type whose CRC is `crc`, or null when none is registered.
func typeFromCrc(crc: u32)->typeinfo?
{
    Sync.sharedLock(&g_HashLock)
    return g_HashCrcToType.tryFind(crc)?.value
}

// Returns the registered type named `name`, or null when none is registered.
//
// `name` is the type's full name; a type without a full name is registered under its bare name.
func typeFromName(name: string)->typeinfo?
{
    Sync.sharedLock(&g_HashLock)
    return g_HashNameToType.tryFind(name)?.value
}

// Returns the registered struct associated with a stable serialization key.
//
// Returns null when the key is unknown or declared by more than one struct.
internal func typeFromKey(key: string)->typeinfo?
{
    Sync.sharedLock(&g_HashLock)
    return g_HashKeyToType.tryFind(key)?.value
}
