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
    let typeAlias = cast(const *TypeInfoAlias) type1
    return __concreteAlias(typeAlias.rawType)
}

func typeIs(toType, fromType: #null typeinfo)->bool
{
    if Swag.typeCmp(toType, fromType, .Strict) do
        return true
    if !toType or !fromType do
        return false
    if fromType.kind != .Struct and fromType.kind != .Interface do
        return false

    let fromStruct = cast(const *TypeInfoStruct) fromType

    for ft in fromStruct.usingFields
    {
        let usingType = __concreteAlias(ft.pointedType!)
        if usingType.kind == .Struct
        {
            let typeStruct = cast(const *Swag.TypeInfoStruct) usingType
            if Swag.typeIs(toType, typeStruct) do
                return true
        }
        elif usingType.kind == .Pointer
        {
            let ptr         = cast(const *Swag.TypeInfoPointer) usingType
            let pointedType = __concreteAlias(ptr.pointedType)
            if pointedType.kind != .Struct do
                continue

            let typeStruct = cast(const *Swag.TypeInfoStruct) pointedType
            if Swag.typeIs(toType, typeStruct) do
                return true
        }
    }

    return false
}

func typeAs(toType, fromType: #null typeinfo, ptr: #null *void)->#null *void
{
    if Swag.typeCmp(toType, fromType, .Strict) do
        return ptr
    if !toType or !fromType or !ptr do
        return null
    if fromType.kind != .Struct and fromType.kind != .Interface do
        return null

    let fromStruct = cast(const *TypeInfoStruct) fromType

    for ft in fromStruct.usingFields
    {
        let usingType = __concreteAlias(ft.pointedType!)
        if usingType.kind == .Struct
        {
            let typeStruct = cast(const *Swag.TypeInfoStruct) usingType
            let subPtr     = cast(*void) (cast([*] u8) ptr + ft.offset)
            let result     = Swag.typeAs(toType, typeStruct, subPtr)
            if result do
                return result
        }
        elif usingType.kind == .Pointer
        {
            let ptrType     = cast(const *Swag.TypeInfoPointer) usingType
            let pointedType = __concreteAlias(ptrType.pointedType)
            if pointedType.kind != .Struct do
                continue

            let fieldPtrAddr = cast(*#null *void) (cast([*] u8) ptr + ft.offset)
            let typeStruct   = cast(const *Swag.TypeInfoStruct) pointedType
            let result       = Swag.typeAs(toType, typeStruct, fieldPtrAddr[])
            if result do
                return result
        }
    }

    return null
}

func typeCmp(typeA, typeB: #null typeinfo, cmpFlags: TypeCmpFlags)->bool
{
    if !typeA and !typeB do
        return true
    if !typeA or !typeB do
        return false
    let type1 = __concreteAlias(typeA)
    let type2 = __concreteAlias(typeB)

    // Cast from any. Fine to cast from a struct or array to a reference
    if cmpFlags & .CastAny and
       type1.kind == TypeInfoKind.Pointer and
       type1.flags & .PointerRef and
       type1.flags & .Const
    {
        let typePointer = cast(const *Swag.TypeInfoPointer) type1
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
        let native1 = cast(const *TypeInfoNative) type1
        let native2 = cast(const *TypeInfoNative) type2
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
        let type1S  = cast(const *TypeInfoStruct) type1
        let type2S  = cast(const *TypeInfoStruct) type2
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

            if !namesAreEqual and field1.name != field2.name do
                return false

            if !Swag.typeCmp(field1.pointedType!, field2.pointedType!, cmpFlags) do
                return false
        }

        return true
    }

    if cmpFlags & .UnScoped do
        return Swag.stringCmp(type1.name, type2.name)
    return Swag.stringCmp(type1.fullname, type2.fullname)
}

////////////////////////////////////////////////////////////

func tableOf(structType, itfType: #null const *TypeInfoStruct)->#null const *void
{
    if !structType or !itfType do
        return null

    let itfs = structType.interfaces
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

func __convertArgcArgv(args: #null const [*] u8)
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
    if !cxt.allocator
    {
        // Under the compiler (JIT) the host installs a process-stable runtime allocator into the
        // context. Building a swag Swag.makeInterface allocator here would place its interface table in
        // per-run JIT memory that is released between workspace modules; if that interface is then
        // cached in a process-persistent imported-DLL global (e.g. a reflection hash table) it
        // dangles and crashes on a later module's allocation. So only build it for native runs.
        if !Swag.jit()
        {
            let allocator = defaultAllocator()
            if !allocator.installed() do
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
    if !(flags & .FromCompiler) do
        Swag.processInfos().args = __osCommandLine()

    discard installAllocator(electricMode: __buildCfg.allocatorElectricMode, detectLeaks: __buildCfg.allocatorLeaks, captureStack: __buildCfg.allocatorCaptureStack, trackAllocations: __buildCfg.allocatorTrackAllocations, fillMemory: __buildCfg.allocatorFillMemory, installInContext: !(flags & .FromCompiler))

    let allocator = __runtimeAllocator()

    cxt.tempAllocator.setCapacity(__buildCfg.tempAllocatorCapacity, allocator)
    cxt.errorAllocator.setCapacity(__buildCfg.errorAllocatorCapacity, allocator)
}

func __releaseRuntime()
{
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
