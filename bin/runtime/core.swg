#global #[Swag.ExplicitNullability]

using Swag

// Special attribute that cannot be defined in the boostrap, because
// we need typeinfo to be defined
namespace Swag
{
    #[AttrUsage(AttributeUsage.All)]
    attr Using(what: #nonull typeinfo...)
}

////////////////////////////////////////////////////////////

func __concreteAlias(type1: #nonull typeinfo)->#nonull typeinfo
{
    if type1.kind != TypeInfoKind.Alias or type1.flags & TypeInfoFlags.Strict do
        return type1
    let typeAlias = cast(#nonull const *TypeInfoAlias) type1
    return __concreteAlias(typeAlias.rawType)
}

func @is(toType, fromType: #nonull typeinfo)->bool
{
    if @typecmp(toType, fromType, .Strict) do
        return true
    if !toType or !fromType do
        return false
    if fromType.kind != .Struct and fromType.kind != .Interface do
        return false

    let fromStruct = cast(#nonull const *TypeInfoStruct) fromType

    for ft in fromStruct.usingFields
    {
        let usingType = __concreteAlias(assume ft.pointedType)
        if usingType.kind == .Struct
        {
            let typeStruct = cast(#nonull const *Swag.TypeInfoStruct) usingType
            if @is(toType, typeStruct) do
                return true
        }
        elif usingType.kind == .Pointer
        {
            let ptr         = cast(#nonull const *Swag.TypeInfoPointer) usingType
            let pointedType = __concreteAlias(ptr.pointedType)
            if pointedType.kind != .Struct do
                continue

            let typeStruct = cast(#nonull const *Swag.TypeInfoStruct) pointedType
            if @is(toType, typeStruct) do
                return true
        }
    }

    return false
}

func @as(toType, fromType: #nonull typeinfo, ptr: #nonull *void)->#null *void
{
    if @typecmp(toType, fromType, .Strict) do
        return ptr
    if !toType or !fromType or !ptr do
        return null
    if fromType.kind != .Struct and fromType.kind != .Interface do
        return null

    let fromStruct = cast(#nonull const *TypeInfoStruct) fromType

    for ft in fromStruct.usingFields
    {
        let usingType = __concreteAlias(assume ft.pointedType)
        if usingType.kind == .Struct
        {
            let typeStruct = cast(#nonull const *Swag.TypeInfoStruct) usingType
            let subPtr     = cast(#nonull *void) (cast(#nonull [*] u8) ptr + ft.offset)
            let result     = @as(toType, typeStruct, subPtr)
            if result do
                return result
        }
        elif usingType.kind == .Pointer
        {
            let ptrType      = cast(#nonull const *Swag.TypeInfoPointer) usingType
            let pointedType  = __concreteAlias(ptrType.pointedType)
            if pointedType.kind != .Struct do
                continue

            let fieldPtrAddr = cast(#nonull *#null *void) (cast(#nonull [*] u8) ptr + ft.offset)
            let typeStruct   = cast(#nonull const *Swag.TypeInfoStruct) pointedType
            let result       = @as(toType, typeStruct, dref fieldPtrAddr)
            if result do
                return result
        }
    }

    return null
}

func @typecmp(typeA, typeB: #nonull typeinfo, cmpFlags: TypeCmpFlags)->bool
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
        let typePointer = cast(#nonull const *Swag.TypeInfoPointer) type1
        return @typecmp(typePointer.pointedType, type2, cmpFlags)
    }

    if (type1.kind != type2.kind) or (type1.sizeof != type2.sizeof) do
        return false

    // HACK for now : do not take care of Nullable flag
    let flags1 = type1.flags & ~.Nullable
    let flags2 = type2.flags & ~.Nullable
    if flags1 != flags2 do
        return false

    // For tuples, we compare field by field
    if type1.flags & .Tuple
    {
        let type1S = cast(#nonull const *TypeInfoStruct) type1
        let type2S = cast(#nonull const *TypeInfoStruct) type2
        for i in @countof(type1S.fields)
        {
            let field1 = type1S.fields[i]
            let field2 = type2S.fields[i]

            var namesAreEqual = false
            if field1.flags & .AutoName do
                namesAreEqual = true
            if field2.flags & .AutoName do
                namesAreEqual = true

            if !namesAreEqual and field1.name != field2.name do
                return false

            if !@typecmp(assume field1.pointedType, assume field2.pointedType, cmpFlags) do
                return false
        }

        return true
    }

    if cmpFlags & .UnScoped do
        return @stringcmp(type1.name, type2.name)
    return @stringcmp(type1.fullname, type2.fullname)
}

////////////////////////////////////////////////////////////

func @tableof(structType, itfType: #nonull const *TypeInfoStruct)->#null const *void
{
    if !structType or !itfType do
        return null

    for i in @countof(structType.interfaces)
    {
        if @stringcmp(structType.interfaces[i].name, itfType.fullname) do
            return structType.interfaces[i].value
    }

    return null
}

////////////////////////////////////////////////////////////

const __MAX_ARGUMENTS = 512
var __argv:           [__MAX_ARGUMENTS] #nonull string = undefined
var __argc            = 0'u32

func __convertArgcArgv(args: #null const [*] u8)
{
    if args == null do
        return

    var cmdLine = args
    __argc = 0
    while dref cmdLine
    {
        while dref cmdLine == ' ' do
            cmdLine += 1
        if dref cmdLine == 0 do
            break

        if dref cmdLine == '"'
        {
            cmdLine += 1
            let start = cmdLine
            while dref cmdLine and dref cmdLine != '"' do
                cmdLine += 1
            __argv[__argc] = cast(#nonull string) @mkslice(start, cast(u64) (cmdLine - start))
            if dref cmdLine do
                cmdLine += 1
        }
        else
        {
            let start = cmdLine
            while dref cmdLine and dref cmdLine != ' ' do
                cmdLine += 1
            __argv[__argc] = cast(#nonull string) @mkslice(start, cast(u64) (cmdLine - start))
        }

        __argc += 1
        if __argc == __MAX_ARGUMENTS do
            return
        while dref cmdLine and dref cmdLine == ' ' do
            cmdLine += 1
    }
}

func @args()->#nonull const [..] #nonull string
{
    if __argc == 0 do
        __convertArgcArgv(@dataof(@pinfos.args))
    return @mkslice(&__argv[0], cast(u64) __argc)
}

////////////////////////////////////////////////////////////

// Make a build configuration copy
const __buildCfg = #run dref @compiler.getBuildCfg()

func @rtflags()  => @getcontext().runtimeFlags
func @jit()->bool => @getcontext().runtimeFlags & .FromCompiler ? true : false

func __runtimeAllocator()->IAllocator
{
    let cxt = @getcontext()
    if cxt.allocator == null
    {
        // Under the compiler (JIT) the host installs a process-stable runtime allocator into the
        // context. Building a swag @mkinterface allocator here would place its interface table in
        // per-run JIT memory that is released between workspace modules; if that interface is then
        // cached in a process-persistent imported-DLL global (e.g. a reflection hash table) it
        // dangles and crashes on a later module's allocation. So only build it for native runs.
        if !@jit()
        {
            let allocator = defaultAllocator()
            if !allocator.installed() do
                allocator.setup()
            cxt.allocator        = @mkinterface(allocator, #typeof(dref allocator), IAllocator)
            cxt.defaultAllocator = cxt.allocator
        }
    }
    return cxt.allocator
}

func __ensureRuntimeAllocator()
{
    let _ = __runtimeAllocator()
}

func __resetRuntimeContext()
{
    let cxt       = @getcontext()
    let allocator = __runtimeAllocator()

    cxt.tempAllocator.release()
    cxt.errorAllocator.release()

    @memset(cxt, 0, #sizeof(Swag.Context))
    cxt.allocator        = allocator
    cxt.defaultAllocator = allocator
}

func __setupRuntime(flags: RuntimeFlags)
{
    __resetRuntimeContext()

    let cxt = @getcontext()
    cxt.runtimeFlags = flags

    discard installAllocator(electricMode: __buildCfg.allocatorElectricMode, detectLeaks: __buildCfg.allocatorLeaks, captureStack: __buildCfg.allocatorCaptureStack, trackAllocations: __buildCfg.allocatorTrackAllocations, fillMemory: __buildCfg.allocatorFillMemory, installInContext: !(flags & .FromCompiler))

    let allocator = __runtimeAllocator()

    cxt.tempAllocator.setCapacity(__buildCfg.tempAllocatorCapacity, allocator)
    cxt.errorAllocator.setCapacity(__buildCfg.errorAllocatorCapacity, allocator)
}

func __releaseRuntime()
{
    let cxt = @getcontext()

    cxt.tempAllocator.release()
    cxt.errorAllocator.release()

    releaseAllocatorThreadCache()

    let allocator = defaultAllocator()
    allocator.release()

    @memset(cxt, 0, #sizeof(Swag.Context))
}

func __closeRuntime()
{
    __exit()
}

func __dropGlobalVariables()
{
    for g in @gvtd
    {
        var ptr = cast(#null [*] u8) g.ptr
        for x in g.count
        {
            g.opDrop(ptr)
            ptr += g.sizeOf
        }
    }
}
