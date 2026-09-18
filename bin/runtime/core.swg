using Swag

// Special attribute that cannot be defined in the boostrap, because
// we need typeinfo to be defined
namespace Swag
{
    #[AttrUsage(AttributeUsage.All)]
    attr Using(what: typeinfo...)
}

////////////////////////////////////////////////////////////

func __concreteAlias(type1: typeinfo)->typeinfo
{
    if type1.kind != TypeInfoKind.Alias or type1.flags & TypeInfoFlags.Strict do
        return type1
    let typeAlias = cast(const *TypeInfoAlias) cast(const *void) type1
    return __concreteAlias(typeAlias.rawType)
}

func __typeCompatible(toType, fromType: typeinfo?)->bool => __runtimeTypeCast(toType, fromType) != null

func __borrowAnyValue(toType, fromType: typeinfo?, ptr: *void?)->*void?
{
    if toType == null or fromType == null or ptr == null do
        return null
    return __findDynamicView(toType, fromType, ptr, null, true)
}

struct DynamicViewVisit
{
    type:     typeinfo
    address:  *void?
    previous: const *DynamicViewVisit?
}

#[Swag.Inline]
func __findDynamicView(toType, fromType: typeinfo, ptr: *void?, view: *Interface?, readOnly: bool)->*void? => __findDynamicViewImpl(toType, fromType, ptr, view, readOnly, null)

func __findDynamicViewImpl(toType, fromType: typeinfo, ptr: *void?, view: *Interface?, readOnly: bool, previous: const *DynamicViewVisit?)->*void?
{
    if Swag.typeCmp(toType, fromType, .Strict) do
        return ptr
    if fromType.kind != .Struct do
        return null

    let fromStruct = cast(const *TypeInfoStruct) cast(const *void) fromType
    if toType.kind == .Interface
    {
        // The object's metadata carries its own tables, including across modules.
        // A dynamic lookup does not need to enumerate unrelated implementations.
        for entry in fromStruct.interfaces where Swag.typeCmp(entry.pointedType, toType, .Strict)
        {
            if let table = entry.value
            {
                if view != null do
                    view.itable = cast(const [*] ([*] void?)) table
                return ptr
            }
        }
    }

    if ptr == null do
        return null
    var visit = previous
    while visit
    {
        if visit.address == ptr and cast(const *void) visit.type == cast(const *void) fromType do
            return null
        visit = visit.previous
    }

    let current = DynamicViewVisit{fromType, ptr, previous}
    for field in fromStruct.usingFields
    {
        var fieldType = __concreteAlias(field.pointedType!)
        if fieldType.flags & .Const and not readOnly do
            continue
        var fieldPtr = cast(*void?) (cast([*] u8) ptr + field.offset)
        if fieldType.kind == .Pointer
        {
            let pointerType = cast(const *TypeInfoPointer) cast(const *void) fieldType
            fieldType = __concreteAlias(pointerType.pointedType)
            fieldPtr  = (cast(*(*void?)) fieldPtr!)[]
        }

        if fieldPtr == null do
            continue
        if let found = __findDynamicViewImpl(toType, fieldType, fieldPtr, view, readOnly, &current) do
            return found
    }

    return null
}

func __hasDynamicBase(toType, fromType: typeinfo)->bool
{
    if Swag.typeCmp(toType, fromType, .Strict) do
        return true
    if fromType.kind != .Struct do
        return false
    let info = cast(const *TypeInfoStruct) cast(const *void) fromType
    for field in info.usingFields
    {
        let fieldType = __concreteAlias(field.pointedType!)
        if fieldType.kind == .Struct and __hasDynamicBase(toType, fieldType) do
            return true
    }

    return false
}

func __containsDynamicSubobject(toType, fromType: typeinfo, ptr, expected: *void)->bool
{
    if ptr == expected and Swag.typeCmp(toType, fromType, .Strict) do
        return true
    if fromType.kind != .Struct do
        return false
    let info = cast(const *TypeInfoStruct) cast(const *void) fromType
    for field in info.usingFields
    {
        let fieldType = __concreteAlias(field.pointedType!)
        if fieldType.kind != .Struct do
            continue
        let fieldPtr = cast(*void) (cast([*] u8) ptr + field.offset)
        if __containsDynamicSubobject(toType, fieldType, fieldPtr, expected) do
            return true
    }

    return false
}

func __findDynamicOwner(toType, fromType: typeinfo, ptr: *void, sourceType: typeinfo, sourcePtr: *void)->*void?
{
    if Swag.typeCmp(toType, fromType, .Strict) and __containsDynamicSubobject(sourceType, fromType, ptr, sourcePtr) do
        return ptr
    if fromType.kind != .Struct do
        return null
    let info = cast(const *TypeInfoStruct) cast(const *void) fromType
    for field in info.usingFields
    {
        let fieldType = __concreteAlias(field.pointedType!)
        if fieldType.kind != .Struct do
            continue
        let fieldPtr = cast(*void) (cast([*] u8) ptr + field.offset)
        if let found = __findDynamicOwner(toType, fieldType, fieldPtr, sourceType, sourcePtr) do
            return found
    }

    return null
}

#[Swag.Inline]
func __dynamicCast(toType, fromType: typeinfo?, ptr: *void?, view: *Interface?, allowNullObject: bool, matchedNull: *bool?)->*void? => __dynamicCastImpl(toType, fromType, ptr, view, allowNullObject, matchedNull, false, false)

func __dynamicCastImpl(toType, fromType: typeinfo?, ptr: *void?, view: *Interface?, allowNullObject: bool, matchedNull: *bool?, borrowValue, readOnly: bool)->*void?
{
    if matchedNull != null do
        matchedNull[] = false
    if view != null do
        view.itable = null
    if toType == null or fromType == null do
        return null
    let requestedType = __concreteAlias(toType)
    let targetIsConst = readOnly or (requestedType.flags & .Const) != 0
    var targetType    = requestedType
    if not borrowValue and requestedType.kind == .Pointer do
        targetType = __concreteAlias((cast(const *TypeInfoPointer) cast(const *void) requestedType).pointedType)
    if borrowValue do
        targetType = targetType.unqualified!
    var sourceType = __concreteAlias(fromType)
    if sourceType.kind != .Pointer and sourceType.kind != .Interface and sourceType.flags & .Const
    {
        if not targetIsConst do
            return null
        sourceType = sourceType.unqualified!
    }

    var sourcePtr         = ptr
    var acceptsNullObject = allowNullObject

    // A boxed null literal has no object address, but is a valid nullable pointer value.
    if matchedNull != null and requestedType.kind == .Pointer and Swag.typeCmp(sourceType, #typeof(null), .Strict)
    {
        matchedNull[] = true
        return null
    }

    if ptr == null and not allowNullObject do
        return null

    // 'any' can hold either an object or a pointer to it. An exact pointer-type
    // request still borrows the stored pointer value instead of dereferencing it.
    if sourceType.kind == .Pointer and not Swag.typeCmp(targetType, sourceType, .Strict)
    {
        if sourceType.flags & .Const and not targetIsConst do
            return null
        if sourcePtr == null do
            return null
        let pointerType = cast(const *TypeInfoPointer) cast(const *void) sourceType
        sourceType = __concreteAlias(pointerType.pointedType)
        sourcePtr  = (cast(*(*void?)) sourcePtr)[]
        if sourcePtr == null and matchedNull != null do
            matchedNull[] = Swag.typeCmp(targetType, sourceType, .Strict) or
                            __hasDynamicBase(targetType, sourceType) or
                            __hasDynamicBase(sourceType, targetType)
        acceptsNullObject = false
    }

    if sourcePtr == null and not acceptsNullObject do
        return null

    // Boxing an interface retains its interface representation in 'any'. Open
    // that representation before inspecting the concrete object's metadata.
    if sourceType.kind == .Interface and (view != null or not Swag.typeCmp(targetType, sourceType, .Strict))
    {
        if sourceType.flags & .Const and not targetIsConst do
            return null
        if sourcePtr == null do
            return null
        let sourceView = cast(*Interface) sourcePtr
        if sourceView.itable == null do
            return null
        sourceType        = cast(const *TypeInfo) sourceView.itable[0]!
        sourcePtr         = sourceView.obj
        acceptsNullObject = true
    }

    if sourcePtr == null
    {
        if acceptsNullObject and view != null do
            return __findDynamicView(targetType, sourceType, null, view, targetIsConst)
        return null
    }

    let originType = sourceType
    let originPtr  = sourcePtr
    let needsOwner = targetType.kind == .Struct and __hasDynamicBase(originType, targetType)
    if not needsOwner and targetType.kind != .Interface
    {
        if let found = __findDynamicView(targetType, sourceType, sourcePtr, view, targetIsConst) do
            return found
    }

    if sourceType.kind == .Struct
    {
        let structType = cast(const *TypeInfoStruct) cast(const *void) sourceType
        if let slots = structType.dynamicSlots
        {
            let slotAddress = cast([*] u8) sourcePtr + slots[0].offset
            let descriptor  = (cast(*const *DynamicStructInfo) cast(*void) slotAddress)[]
            sourcePtr  = cast(*void) (slotAddress - descriptor.offset)
            sourceType = descriptor.type
        }
    }

    // Match the actual source subobject, not the first base with the same type.
    // This also makes a checked inverse cast agree with its fixed-offset form.
    if needsOwner do
        return __findDynamicOwner(targetType, sourceType, sourcePtr, originType, originPtr)
    return __findDynamicView(targetType, sourceType, sourcePtr, view, targetIsConst)
}

// A descriptor's public fields describe a type; only the hidden self reference proves
// that this descriptor was issued by the compiler. Copying the fields cannot forge it.
func __isCompilerType(type: typeinfo?)->bool
{
    if type == null do
        return false
    const identityOffset = #sizeof(TypeInfo) - #sizeof(*void)
    let address  = cast(const [*] u8) cast(const *void) type + identityOffset
    let identity = (cast(const *const *DynamicStructInfo) address)[]
    return cast(const *void?) identity.runtimeType == cast(const *void) type
}

struct RuntimeTypeCastVisit
{
    type:     typeinfo
    target:   typeinfo
    previous: const *RuntimeTypeCastVisit?
}

func __runtimeTypeCompatible(toType, fromType: typeinfo, previous: const *RuntimeTypeCastVisit?, readOnly = false)->bool
{
    let target = __concreteAlias(toType)
    let source = __concreteAlias(fromType)
    if source.flags & .Nullable and not (target.flags & .Nullable) do
        return false
    if (source.kind == .Pointer or source.kind == .Interface) and source.flags & .Const and not (target.flags & .Const) do
        return false
    let plainTarget = target.unqualified!
    let plainSource = source.unqualified!
    if Swag.typeCmp(plainTarget, plainSource, .Strict) do
        return true
    var visit = previous
    while visit
    {
        if cast(const *void) visit.type == cast(const *void) source and cast(const *void) visit.target == cast(const *void) target do
            return false
        visit = visit.previous
    }

    let current = RuntimeTypeCastVisit{source, target, previous}
    if source.kind == .Pointer
    {
        let pointer = cast(const *TypeInfoPointer) cast(const *void) source
        if target.kind == .Interface do
            return __runtimeTypeCompatible(target, pointer.pointedType, &current, (target.flags & .Const) != 0)
        if target.kind != .Pointer do
            return false
        let targetPointer = cast(const *TypeInfoPointer) cast(const *void) target
        if Swag.typeCmp(targetPointer.pointedType, pointer.pointedType, .Strict) do
            return true
        return __runtimeTypeCompatible(targetPointer.pointedType, pointer.pointedType, &current, (target.flags & .Const) != 0)
    }

    if source.kind != .Struct do
        return false
    let info = cast(const *TypeInfoStruct) cast(const *void) source
    if target.kind == .Interface
    {
        for entry in info.interfaces where entry.value != null
        {
            if Swag.typeCmp(entry.pointedType, plainTarget, .Strict) do
                return true
        }
    }

    for field in info.usingFields
    {
        var fieldType = __concreteAlias(field.pointedType!)
        if fieldType.flags & .Const and not readOnly and not (target.flags & .Const) do
            continue
        if fieldType.kind == .Pointer do
            fieldType = (cast(const *TypeInfoPointer) cast(const *void) fieldType).pointedType
        if __runtimeTypeCompatible(target, fieldType, &current, readOnly or (target.flags & .Const) != 0) do
            return true
    }

    return false
}

func __runtimeTypeCast(toType, fromType: typeinfo?)->typeinfo?
{
    if not __isCompilerType(toType) or not __isCompilerType(fromType) do
        return null
    if __runtimeTypeCompatible(toType!, fromType!, null) do
        return fromType
    return null
}

struct RuntimeValueCastStorage
{
    value: const any?
    view:  Interface
}

#assert(#sizeof(RuntimeValueCastStorage) == 4 * #sizeof(u64))

func __runtimeValueCast(toType: typeinfo?, source: const *(any?), storage: *void, readOnly: bool)->bool
{
    let result = cast(*RuntimeValueCastStorage) storage
    result.value       = null
    result.view.obj    = null
    result.view.itable = null
    if not __isCompilerType(toType) or source[] == null do
        return false
    let sourceType = Swag.kindOf(source[])
    if not __isCompilerType(sourceType) do
        return false
    let target = toType!
    if Swag.typeCmp(target, sourceType, .Strict)
    {
        result.value = source[]
        return true
    }

    // Borrowing a pointer value cannot change its pointee type or constness in place.
    if target.kind == .Pointer do
        return false
    let view: *Interface? = target.kind == .Interface ? &result.view : null

    // The result's constness is carried by the cast expression; lookup only reads this address.
    let sourceData = cast #unconst(*void?) cast(const *void?) source[].buffer
    let found      = __dynamicCastImpl(target, sourceType, sourceData, view, false, null, true, readOnly)
    if target.kind == .Interface
    {
        if result.view.itable == null do
            return false
        result.view.obj = found
        result.value    = Swag.makeAny(&result.view, target)
        return true
    }

    if found == null do
        return false
    result.value = Swag.makeAny(found, target)
    return true
}

func typeCmp(typeA, typeB: typeinfo?, cmpFlags: TypeCmpFlags)->bool
{
    if not typeA and not typeB do
        return true
    if not typeA or not typeB do
        return false
    let type1 = __concreteAlias(typeA)
    let type2 = __concreteAlias(typeB)

    // Cast from any. Fine to cast from a struct or array to a reference
    if cmpFlags & .CastAny and
       type1.kind == TypeInfoKind.Pointer and
       type1.flags & .PointerRef and
       type1.flags & .Const
    {
        let typePointer = cast(const *Swag.TypeInfoPointer) cast(const *void) type1
        return Swag.typeCmp(typePointer.pointedType, type2, cmpFlags)
    }

    if (type1.kind != type2.kind) or (type1.sizeof != type2.sizeof) do
        return false

    // Nullability and explicit initialization are source contracts, not runtime type identity.
    let nullableFlags = TypeInfoFlags.Nullable | TypeInfoFlags.RequiresExplicitInit
    let flags1        = type1.flags & ~nullableFlags
    let flags2        = type2.flags & ~nullableFlags
    if flags1 != flags2 do
        return false

    if type1.kind == TypeInfoKind.Native
    {
        let native1 = cast(const *TypeInfoNative) cast(const *void) type1
        let native2 = cast(const *TypeInfoNative) cast(const *void) type2
        if native1.nativeKind != native2.nativeKind do
            return false
        if native1.nativeKind == TypeInfoNativeKind.String or
           native1.nativeKind == TypeInfoNativeKind.CString or
           native1.nativeKind == TypeInfoNativeKind.Any do
            return true
    }

    // For tuples, we compare field by field
    if type1.flags & .Tuple
    {
        let type1S  = cast(const *TypeInfoStruct) cast(const *void) type1
        let type2S  = cast(const *TypeInfoStruct) cast(const *void) type2
        let fields1 = type1S.fields
        let fields2 = type2S.fields
        if fields1 == null or fields2 == null do
            return fields1.count == fields2.count

        for i in fields1.count
        {
            let field1 = fields1[i]
            let field2 = fields2[i]

            var namesAreEqual = false
            if field1.flags & .AutoName do
                namesAreEqual = true
            if field2.flags & .AutoName do
                namesAreEqual = true

            if not namesAreEqual and field1.name != field2.name do
                return false

            if not Swag.typeCmp(field1.pointedType!, field2.pointedType!, cmpFlags) do
                return false
        }

        return true
    }

    if cmpFlags & .UnScoped do
        return Swag.stringCmp(type1.name, type2.name)
    return Swag.stringCmp(type1.fullname, type2.fullname)
}

////////////////////////////////////////////////////////////

func tableOf(structType, itfType: typeinfo?)->const *void?
{
    if not structType or not itfType or itfType.kind != .Interface do
        return null
    let info = cast #try (const *TypeInfoStruct) structType
    if not info do
        return null
    let itfs = info.interfaces
    if itfs == null do
        return null

    for i in itfs.count
    {
        if Swag.stringCmp(itfs[i].name, itfType.fullname) do
            return itfs[i].value
    }

    return null
}

////////////////////////////////////////////////////////////

const __MAX_ARGUMENTS = 512

// Keep the public `args` slice non-null. The unused capacity holds valid empty strings rather
// than raw string storage; command-line conversion overwrites the prefix it exposes.
var __argv: [__MAX_ARGUMENTS] string = ""
var __argc = 0'u32

func __convertArgcArgv(args: const [*] u8?)
{
    if args == null do
        return

    var cmdLine = args
    __argc = 0
    while cmdLine[]
    {
        while cmdLine[] == ' ' do
            cmdLine += 1
        if cmdLine[] == 0 do
            break

        if cmdLine[] == '"'
        {
            cmdLine += 1
            let start = cmdLine
            while cmdLine[] and cmdLine[] != '"' do
                cmdLine += 1
            __argv[__argc] = cast(string) Swag.makeSlice(start, cast(u64) (cmdLine - start))
            if cmdLine[] do
                cmdLine += 1
        }
        else
        {
            let start = cmdLine
            while cmdLine[] and cmdLine[] != ' ' do
                cmdLine += 1
            __argv[__argc] = cast(string) Swag.makeSlice(start, cast(u64) (cmdLine - start))
        }

        __argc += 1
        if __argc == __MAX_ARGUMENTS do
            return
        while cmdLine[] and cmdLine[] == ' ' do
            cmdLine += 1
    }
}

func args()->const [..] string
{
    if __argc == 0 do
        __convertArgcArgv((Swag.processInfos().args).buffer)
    return Swag.makeSlice(&__argv[0], cast(u64) __argc)
}

////////////////////////////////////////////////////////////

// Make a build configuration copy
const __buildCfg = #run Swag.compiler().getBuildCfg()![]

func runtimeFlags() => Swag.getContext().runtimeFlags
func jit()->bool    => Swag.getContext().runtimeFlags & .FromCompiler ? true : false

func __runtimeAllocator()->IAllocator
{
    let cxt = Swag.getContext()
    if not cxt.allocator
    {
        // Under the compiler (JIT) the host installs a process-stable runtime allocator into the
        // context. Building a swag Swag.makeInterface allocator here would place its interface table in
        // per-run JIT memory that is released between workspace modules; if that interface is then
        // cached in a process-persistent imported-DLL global (e.g. a reflection hash table) it
        // dangles and crashes on a later module's allocation. So only build it for native runs.
        if not Swag.jit()
        {
            let allocator = defaultAllocator()
            if not allocator.installed() do
                allocator.setup()
            cxt.allocator        = Swag.makeInterface(allocator, #typeof(allocator[]), IAllocator)
            cxt.defaultAllocator = cxt.allocator
        }
    }

    return cxt.allocator!
}

func __ensureRuntimeAllocator()
{
    let _ = __runtimeAllocator()
}

func __resetRuntimeContext()
{
    let cxt       = Swag.getContext()
    let allocator = __runtimeAllocator()

    cxt.tempAllocator.release()
    cxt.errorAllocator.release()

    Swag.memset(cxt, 0, #sizeof(Swag.Context))
    cxt.allocator        = allocator
    cxt.defaultAllocator = allocator
}

// Every artifact is x86-64-v3 code: the backend emits VEX-encoded forms unconditionally, so a
// host without AVX2 faults on an illegal instruction somewhere inside the program instead of
// saying why. This runs first in the startup path and touches nothing but the operating system,
// so it stays reachable on the very CPU that cannot execute the rest.
//
// Only a standalone program reaches an unchecked host. Under the compiler the answer is already
// known -- 'swc' refused to start below the baseline before it could run any of this -- and the
// compiler is reached three ways: JIT code, the JIT-run test entry (which carries no flag of its
// own), and the native modules the compiler loads. Ending the process in any of them would kill
// the compiler instead of reporting.
#[Swag.Optimize(false)]
func __checkCpuBaseline(flags: RuntimeFlags)
{
    if Swag.jit() or (flags & .FromCompiler) do
        return
    if __hostHasAvx2() do
        return

    __printString("fatal error: this program needs a CPU with AVX2 (x86-64-v3)\n")
    __exitError()
}

func __setupRuntime(flags: RuntimeFlags)
{
    __checkCpuBaseline(flags)
    __resetRuntimeContext()

    let cxt = Swag.getContext()
    cxt.runtimeFlags = flags

    // A native run owns its command line, and every artifact keeps its own 'Swag.processInfos()', so the
    // executable seeds its copy here and hands it down the hook chain to the modules it imports.
    // Under the compiler the real command line belongs to 'swc' itself; the host has already
    // filled the slot with the one the program is effectively launched with, so leave it alone.
    if not (flags & .FromCompiler) do
        Swag.processInfos().args = __osCommandLine()

    discard installAllocator(electricMode: __buildCfg.allocatorElectricMode, detectLeaks: __buildCfg.allocatorLeaks, captureStack: __buildCfg.allocatorCaptureStack, trackAllocations: __buildCfg.allocatorTrackAllocations, fillMemory: __buildCfg.allocatorFillMemory, installInContext: not (flags & .FromCompiler))

    let allocator = __runtimeAllocator()

    cxt.tempAllocator.setCapacity(__buildCfg.tempAllocatorCapacity, allocator)
    cxt.errorAllocator.setCapacity(__buildCfg.errorAllocatorCapacity, allocator)
}

func __releaseRuntime()
{
    // The worker threads run code from this artifact and allocate through its context, so they
    // must be joined before anything they use is released.
    __shutdownScheduler()

    let cxt = Swag.getContext()

    cxt.tempAllocator.release()
    cxt.errorAllocator.release()

    releaseAllocatorThreadCache()

    let allocator = defaultAllocator()
    allocator.release()

    Swag.memset(cxt, 0, #sizeof(Swag.Context))
}

func __closeRuntime()
{
    __exit()
}

func __dropGlobalVariables()
{
    for g in Swag.gvtd()
    {
        var ptr = cast([*] u8) g.ptr
        for x in g.count
        {
            g.opDrop(ptr)
            ptr += g.sizeOf
        }
    }
}
