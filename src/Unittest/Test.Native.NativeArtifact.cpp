#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/JIT/JITExecManager.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeLinkerCoff.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct NativeArtifactTestFixture
    {
        CommandLine                            cmdLine;
        std::unique_ptr<CompilerInstance>      compiler;
        std::unique_ptr<TaskContext>           compilerCtx;
        std::unique_ptr<NativeBackendBuilder>  nativeBuilder;
        std::unique_ptr<NativeArtifactBuilder> artifactBuilder;

        explicit NativeArtifactTestFixture(const Global& global, CommandLine cmdLine) :
            cmdLine(std::move(cmdLine))
        {
            CommandLineParser::refreshBuildCfg(this->cmdLine);
            compiler    = std::make_unique<CompilerInstance>(global, this->cmdLine);
            compilerCtx = std::make_unique<TaskContext>(*compiler);
            SWC_ASSERT(compiler->setupSema(*compilerCtx) == Result::Continue);
            nativeBuilder   = std::make_unique<NativeBackendBuilder>(*compiler, false);
            artifactBuilder = std::make_unique<NativeArtifactBuilder>(*nativeBuilder);
        }
    };

    fs::path fallbackInputRoot()
    {
        std::error_code ec;
        const fs::path  currentDir = fs::current_path(ec);
        if (ec)
            return {};
        return currentDir.lexically_normal();
    }

    fs::path inputRootForTest(const CommandLine& cmdLine)
    {
        if (!cmdLine.directories.empty())
            return cmdLine.directories.begin()->lexically_normal();
        if (!cmdLine.files.empty())
            return cmdLine.files.begin()->parent_path().lexically_normal();
        if (!cmdLine.modulePath.empty())
            return cmdLine.modulePath.parent_path().lexically_normal();
        return fallbackInputRoot();
    }

    CommandLine makeNativeArtifactCmdLine(const TaskContext& ctx)
    {
        CommandLine    cmdLine = ctx.cmdLine();
        const fs::path root    = inputRootForTest(cmdLine);

        cmdLine.command          = CommandKind::Build;
        cmdLine.name             = "native_paths";
        cmdLine.sourceDrivenTest = false;
        cmdLine.testNative       = true;
        cmdLine.testJit          = true;
        cmdLine.lexOnly          = false;
        cmdLine.syntaxOnly       = false;
        cmdLine.semaOnly         = false;
        cmdLine.output           = true;
        cmdLine.runtime          = true;
        cmdLine.unittest         = false;
        cmdLine.verboseUnittest  = false;
        cmdLine.directories.clear();
        cmdLine.files.clear();
        cmdLine.modulePath.clear();
        cmdLine.outDir.clear();
        cmdLine.workDir.clear();
        cmdLine.outDirStorage.clear();
        cmdLine.workDirStorage.clear();
        cmdLine.backendKind = Runtime::BuildCfgBackendKind::Executable;

        if (!root.empty())
            cmdLine.directories.insert(root);

        CommandLineParser::refreshBuildCfg(cmdLine);
        return cmdLine;
    }

    CommandLine makeStandaloneNativeArtifactCmdLine(const TaskContext& ctx, std::string_view testName, const Runtime::BuildCfgBackendKind artifactKind)
    {
        CommandLine cmdLine = makeNativeArtifactCmdLine(ctx);
        cmdLine.backendKind = artifactKind;

        const fs::path tempRoot = Os::getTemporaryPath();
        SWC_ASSERT(!tempRoot.empty());

        const fs::path outputRoot = tempRoot / "swc_unittest" / std::format("native_artifact_p{}", Os::currentProcessId());
        cmdLine.outDir            = outputRoot / testName;
        cmdLine.workDir           = outputRoot / std::format("{}_work", testName);
        cmdLine.outDirStorage     = Utf8(cmdLine.outDir.lexically_normal().string());
        cmdLine.workDirStorage    = Utf8(cmdLine.workDir.lexically_normal().string());
        cmdLine.clear             = true;
        CommandLineParser::refreshBuildCfg(cmdLine);
        return cmdLine;
    }

    bool containsBytes(const std::vector<std::byte>& bytes, std::string_view value)
    {
        if (value.empty())
            return true;
        if (bytes.size() < value.size())
            return false;

        const auto* begin = reinterpret_cast<const char*>(bytes.data());
        const auto* end   = begin + bytes.size();
        return std::search(begin, end, value.begin(), value.end()) != end;
    }

    SymbolFunction* makeTestFunction(TaskContext& ctx, std::string_view name)
    {
        auto* function = Symbol::make<SymbolFunction>(ctx, nullptr, TokenRef::invalid(), ctx.idMgr().addIdentifier(name), SymbolFlagsE::Zero);
        function->setReturnTypeRef(ctx.typeMgr().typeVoid());
        function->setTyped(ctx);
        function->setSemaCompleted(ctx);
        return function;
    }

    ConstantRef addStringConstant(const TaskContext& ctx, CompilerInstance& compiler, DataSegment& segment, std::string_view value, Runtime::String*& outStorage)
    {
        const auto [stringView, stringOffset]                  = segment.addString(value);
        const auto [runtimeStringOffset, runtimeStringStorage] = segment.reserve<Runtime::String>();
        runtimeStringStorage->ptr                              = stringView.data();
        runtimeStringStorage->length                           = stringView.size();
        segment.addRelocation(runtimeStringOffset + offsetof(Runtime::String, ptr), stringOffset);
        outStorage = runtimeStringStorage;

        const ByteSpan bytes{reinterpret_cast<const std::byte*>(runtimeStringStorage), sizeof(Runtime::String)};
        auto           makeStructBorrowed = ConstantValue::makeStructBorrowed(ctx, compiler.typeMgr().typeString(), bytes);
        makeStructBorrowed.setDataSegmentRef({.shardIndex = 0, .offset = runtimeStringOffset});
        return compiler.cstMgr().addConstant(ctx, makeStructBorrowed);
    }

    void addNativeFunctionInfo(NativeBackendBuilder& nativeBuilder, TaskContext& ctx, MachineCode& code, std::string_view debugName)
    {
        const Utf8 name{debugName};
        const Utf8 symbolName = std::format("__test_{}", debugName);
        nativeBuilder.functionInfos.push_back({
            .symbol      = makeTestFunction(ctx, debugName),
            .machineCode = &code,
            .symbolName  = symbolName,
            .debugName   = name,
        });
    }

    MachineCode makeConstantAddressCode(const ConstantRef constantRef, const void* storage)
    {
        MachineCode code;
        code.bytes.resize(sizeof(uint64_t));
        code.codeRelocations.push_back({
            .kind          = MicroRelocation::Kind::ConstantAddress,
            .codeOffset    = 0,
            .targetAddress = reinterpret_cast<uint64_t>(storage),
            .constantRef   = constantRef,
        });
        return code;
    }

    template<typename FUNC>
    Result runAfterPauses(TaskContext& ctx, const FUNC& func)
    {
        while (true)
        {
            const Result result = func();
            if (result != Result::Pause)
                return result;

            Sema::waitDone(ctx, ctx.compiler().jobClientId());
            if (Stats::hasError())
                return Result::Error;
        }
    }
}

SWC_TEST_BEGIN(NativeArtifact_DefaultsToLocalOutputTree)
{
    const CommandLine cmdLine   = makeNativeArtifactCmdLine(ctx);
    const fs::path    inputRoot = inputRootForTest(cmdLine);
    if (inputRoot.empty())
        return Result::Error;

    CompilerInstance            compiler(ctx.global(), cmdLine);
    NativeBackendBuilder        nativeBuilder(compiler, false);
    const NativeArtifactBuilder artifactBuilder(nativeBuilder);

    NativeArtifactPaths firstPaths;
    artifactBuilder.queryPaths(firstPaths, 3);

    NativeArtifactPaths secondPaths;
    artifactBuilder.queryPaths(secondPaths, 1);

    const fs::path expectedOutputRoot = inputRoot / ".output";
    if (!FileSystem::pathEquals(firstPaths.workDir.parent_path(), expectedOutputRoot))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.outDir, firstPaths.workDir))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.buildDir, firstPaths.workDir))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.artifactPath.parent_path(), firstPaths.workDir))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.pdbPath.parent_path(), firstPaths.workDir))
        return Result::Error;
    if (firstPaths.pdbPath.filename() != fs::path("native_paths.pdb"))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.workDir, secondPaths.workDir))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.buildDir, secondPaths.buildDir))
        return Result::Error;
    if (firstPaths.objectPaths.size() != 3)
        return Result::Error;
    if (secondPaths.objectPaths.size() != 1)
        return Result::Error;

    for (const fs::path& objectPath : firstPaths.objectPaths)
    {
        if (!FileSystem::pathEquals(objectPath.parent_path(), firstPaths.buildDir))
            return Result::Error;
    }

    if (!FileSystem::pathEquals(secondPaths.objectPaths.front().parent_path(), secondPaths.buildDir))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_ImportedApiKeepsLocalOutputTree)
{
    CommandLine                 cmdLine   = makeNativeArtifactCmdLine(ctx);
    const fs::path              inputRoot = inputRootForTest(cmdLine);
    CompilerInstance            compiler(ctx.global(), cmdLine);
    NativeBackendBuilder        nativeBuilder(compiler, false);
    const NativeArtifactBuilder artifactBuilder(nativeBuilder);

    if (inputRoot.empty())
        return Result::Error;

    cmdLine.importApiDirs.insert(inputRoot.parent_path().parent_path() / ".output" / "dep" / "win32");
    CompilerInstance            compilerWithImport(ctx.global(), cmdLine);
    NativeBackendBuilder        nativeBuilderWithImport(compilerWithImport, false);
    const NativeArtifactBuilder artifactBuilderWithImport(nativeBuilderWithImport);

    NativeArtifactPaths pathsWithoutImport;
    artifactBuilder.queryPaths(pathsWithoutImport, 1);

    NativeArtifactPaths pathsWithImport;
    artifactBuilderWithImport.queryPaths(pathsWithImport, 1);

    const fs::path expectedOutputRoot = inputRoot / ".output";
    if (!FileSystem::pathEquals(pathsWithImport.workDir.parent_path(), expectedOutputRoot))
        return Result::Error;
    if (!FileSystem::pathEquals(pathsWithoutImport.workDir.parent_path(), pathsWithImport.workDir.parent_path()))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_ModuleNamespaceDefaultsFromModulePath)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Build;
    cmdLine.buildCfg    = "debug";
    cmdLine.backendKind = Runtime::BuildCfgBackendKind::SharedLibrary;
    cmdLine.modulePath  = fs::path("bin/std/modules/win32");
    CommandLineParser::refreshBuildCfg(cmdLine);

    if (Utf8(cmdLine.defaultBuildCfg.moduleNamespace) != "Win32")
        return Result::Error;

    CompilerInstance            compiler(ctx.global(), cmdLine);
    NativeBackendBuilder        nativeBuilder(compiler, false);
    const NativeArtifactBuilder artifactBuilder(nativeBuilder);
    NativeArtifactPaths         paths;
    artifactBuilder.queryPaths(paths, 0);
    if (paths.name != "win32")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_ModuleNamespaceOverrideWins)
{
    CommandLine cmdLine;
    cmdLine.command         = CommandKind::Build;
    cmdLine.buildCfg        = "debug";
    cmdLine.backendKind     = Runtime::BuildCfgBackendKind::SharedLibrary;
    cmdLine.modulePath      = fs::path("bin/std/modules/win32");
    cmdLine.moduleNamespace = "WindowsSdk";
    CommandLineParser::refreshBuildCfg(cmdLine);

    if (Utf8(cmdLine.defaultBuildCfg.moduleNamespace) != "WindowsSdk")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_ExplicitArtifactKindOverridesBuildCfgMutation)
{
    CommandLine cmdLine;
    cmdLine.command              = CommandKind::Build;
    cmdLine.buildCfg             = "debug";
    cmdLine.backendKind          = Runtime::BuildCfgBackendKind::SharedLibrary;
    cmdLine.artifactKindExplicit = true;
    CommandLineParser::refreshBuildCfg(cmdLine);

    if (effectiveBackendKind(cmdLine, Runtime::BuildCfgBackendKind::StaticLibrary) != Runtime::BuildCfgBackendKind::SharedLibrary)
        return Result::Error;
    if (effectiveBackendKind(cmdLine, Runtime::BuildCfgBackendKind::Executable) != Runtime::BuildCfgBackendKind::SharedLibrary)
        return Result::Error;

    cmdLine.artifactKindExplicit = false;
    if (effectiveBackendKind(cmdLine, Runtime::BuildCfgBackendKind::StaticLibrary) != Runtime::BuildCfgBackendKind::StaticLibrary)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_RDataKeepsOnlyReferencedConstants)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine(ctx, "rdata_keeps_only_referenced_constants", Runtime::BuildCfgBackendKind::SharedLibrary);

    const NativeArtifactTestFixture fixture(ctx.global(), commandLine);

    constexpr auto referencedMarker   = "__native_rdata_referenced_marker__";
    constexpr auto unreferencedMarker = "__native_rdata_unreferenced_marker__";

    DataSegment&      segment                   = fixture.compiler->cstMgr().shardDataSegment(0);
    Runtime::String*  referencedRuntimeString   = nullptr;
    Runtime::String*  unreferencedRuntimeString = nullptr;
    const ConstantRef referencedStringRef       = addStringConstant(*fixture.compilerCtx, *fixture.compiler, segment, referencedMarker, referencedRuntimeString);
    SWC_UNUSED(addStringConstant(*fixture.compilerCtx, *fixture.compiler, segment, unreferencedMarker, unreferencedRuntimeString));

    MachineCode code = makeConstantAddressCode(referencedStringRef, referencedRuntimeString);
    addNativeFunctionInfo(*fixture.nativeBuilder, *fixture.compilerCtx, code, "rdata_referenced");

    SWC_RESULT(fixture.artifactBuilder->build());

    if (!containsBytes(fixture.nativeBuilder->mergedRData.bytes, referencedMarker))
        return Result::Error;
    if (containsBytes(fixture.nativeBuilder->mergedRData.bytes, unreferencedMarker))
        return Result::Error;
    if (fixture.nativeBuilder->mergedRData.relocations.size() != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_RDataAllowsInteriorConstantAddresses)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine(ctx, "rdata_allows_interior_constant_addresses", Runtime::BuildCfgBackendKind::SharedLibrary);

    const NativeArtifactTestFixture fixture(ctx.global(), commandLine);

    constexpr auto referencedMarker = "__native_rdata_interior_constant_marker__";

    DataSegment&      segment                 = fixture.compiler->cstMgr().shardDataSegment(0);
    Runtime::String*  referencedRuntimeString = nullptr;
    const ConstantRef referencedStringRef     = addStringConstant(*fixture.compilerCtx, *fixture.compiler, segment, referencedMarker, referencedRuntimeString);

    const auto* interiorAddress = reinterpret_cast<const std::byte*>(referencedRuntimeString) + offsetof(Runtime::String, length);
    MachineCode code            = makeConstantAddressCode(referencedStringRef, interiorAddress);
    addNativeFunctionInfo(*fixture.nativeBuilder, *fixture.compilerCtx, code, "rdata_interior_constant");

    SWC_RESULT(fixture.artifactBuilder->build());

    if (!containsBytes(fixture.nativeBuilder->mergedRData.bytes, referencedMarker))
        return Result::Error;
    if (fixture.nativeBuilder->mergedRData.relocations.size() != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_LinkerOutputFilterSuppressesDllImportLibraryLine)
{
    if (NativeLinkerCoff::shouldForwardLinkerOutputLine("   Creating library foo.lib and object foo.exp", true))
        return Result::Error;
    if (!NativeLinkerCoff::shouldForwardLinkerOutputLine("   Creating library foo.lib and object foo.exp", false))
        return Result::Error;
    if (!NativeLinkerCoff::shouldForwardLinkerOutputLine("LINK : warning LNK4098: defaultlib 'MSVCRT' conflicts with use of other libs", true))
        return Result::Error;
    if (!NativeLinkerCoff::shouldForwardLinkerOutputLine("Creating library_without_object_message", true))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_RDataKeepsReferencedDependencies)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine(ctx, "rdata_keeps_referenced_dependencies", Runtime::BuildCfgBackendKind::SharedLibrary);

    const NativeArtifactTestFixture fixture(ctx.global(), commandLine);

    constexpr auto dependencyMarker = "__native_rdata_dependency_marker__";

    DataSegment& segment                     = fixture.compiler->cstMgr().shardDataSegment(0);
    const auto [stringView, stringOffset]    = segment.addString(dependencyMarker);
    const auto [nestedOffset, nestedStorage] = segment.reserve<uint64_t>();
    *nestedStorage                           = reinterpret_cast<uint64_t>(stringView.data());
    segment.addRelocation(nestedOffset, stringOffset);

    const auto [rootOffset, rootStorage] = segment.reserve<uint64_t>();
    *rootStorage                         = reinterpret_cast<uint64_t>(nestedStorage);
    segment.addRelocation(rootOffset, nestedOffset);

    ConstantValue value = ConstantValue::makeValuePointer(*fixture.compilerCtx,
                                                          fixture.compiler->typeMgr().typeU8(),
                                                          reinterpret_cast<uint64_t>(rootStorage),
                                                          TypeInfoFlagsE::Const);
    value.setDataSegmentRef({.shardIndex = 0, .offset = rootOffset});
    const ConstantRef rootRef = fixture.compiler->cstMgr().addConstant(*fixture.compilerCtx, value);

    MachineCode code = makeConstantAddressCode(rootRef, rootStorage);
    addNativeFunctionInfo(*fixture.nativeBuilder, *fixture.compilerCtx, code, "rdata_dependency");

    SWC_RESULT(fixture.artifactBuilder->build());

    if (!containsBytes(fixture.nativeBuilder->mergedRData.bytes, dependencyMarker))
        return Result::Error;
    if (fixture.nativeBuilder->mergedRData.relocations.size() != 2)
        return Result::Error;

    uint32_t emittedRootOffset   = 0;
    uint32_t emittedNestedOffset = 0;
    uint32_t emittedStringOffset = 0;
    if (!fixture.nativeBuilder->tryMapRDataSourceOffset(emittedRootOffset, 0, rootOffset))
        return Result::Error;
    if (!fixture.nativeBuilder->tryMapRDataSourceOffset(emittedNestedOffset, 0, nestedOffset))
        return Result::Error;
    if (!fixture.nativeBuilder->tryMapRDataSourceOffset(emittedStringOffset, 0, stringOffset))
        return Result::Error;
    if (emittedRootOffset == emittedNestedOffset || emittedNestedOffset == emittedStringOffset)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_RDataEmitsFunctionRelocations)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine(ctx, "rdata_emits_function_relocations", Runtime::BuildCfgBackendKind::SharedLibrary);

    const NativeArtifactTestFixture fixture(ctx.global(), commandLine);

    MachineCode targetCode;
    targetCode.bytes.push_back(std::byte{0xC3});

    auto* targetFunction = makeTestFunction(*fixture.compilerCtx, "rdata_target");
    fixture.nativeBuilder->functionInfos.push_back({
        .symbol      = targetFunction,
        .machineCode = &targetCode,
        .symbolName  = "__test_rdata_target",
        .debugName   = "rdata_target",
    });

    DataSegment& segment                   = fixture.compiler->cstMgr().shardDataSegment(0);
    const auto [tableOffset, tableStorage] = segment.reserve<uint64_t>();
    *tableStorage                          = 0;
    segment.addFunctionRelocation(tableOffset, targetFunction);

    ConstantValue value = ConstantValue::makeValuePointer(*fixture.compilerCtx,
                                                          fixture.compiler->typeMgr().typeVoid(),
                                                          reinterpret_cast<uint64_t>(tableStorage),
                                                          TypeInfoFlagsE::Const);
    value.setDataSegmentRef({.shardIndex = 0, .offset = tableOffset});
    const ConstantRef rootRef = fixture.compiler->cstMgr().addConstant(*fixture.compilerCtx, value);

    MachineCode ownerCode = makeConstantAddressCode(rootRef, tableStorage);
    addNativeFunctionInfo(*fixture.nativeBuilder, *fixture.compilerCtx, ownerCode, "rdata_owner");

    fixture.nativeBuilder->functionBySymbol.clear();
    for (const auto& info : fixture.nativeBuilder->functionInfos)
        fixture.nativeBuilder->functionBySymbol.emplace(info.symbol, &info);

    SWC_RESULT(fixture.artifactBuilder->build());

    if (fixture.nativeBuilder->mergedRData.relocations.size() != 1)
        return Result::Error;

    const NativeSectionRelocation& relocation = fixture.nativeBuilder->mergedRData.relocations.front();
    if (relocation.symbolName != "__test_rdata_target")
        return Result::Error;
    if (relocation.addend != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_StartupCallsRuntimeExitWrapper)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine(ctx, "startup_calls_runtime_exit_wrapper", Runtime::BuildCfgBackendKind::Executable);

    const NativeArtifactTestFixture fixture(ctx.global(), commandLine);

    auto* mainFunction = makeTestFunction(*fixture.compilerCtx, "main");
    auto* exitFunction = makeTestFunction(*fixture.compilerCtx, "__exit");
    fixture.compiler->registerRuntimeFunctionSymbol(fixture.compilerCtx->idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::Exit), exitFunction);
    fixture.nativeBuilder->mainFunctions.push_back(mainFunction);

    SWC_RESULT(fixture.artifactBuilder->build());

    if (!fixture.nativeBuilder->startup)
        return Result::Error;

    bool foundExitRelocation = false;
    for (const auto& relocation : fixture.nativeBuilder->startup->code.codeRelocations)
    {
        if (relocation.targetSymbol != exitFunction)
            continue;

        if (relocation.kind != MicroRelocation::Kind::LocalFunctionAddress)
            return Result::Error;

        foundExitRelocation = true;
    }

    if (!foundExitRelocation)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable)
{
    static constexpr std::string_view SOURCE     = R"(#global fileprivate
var GValue: s32 = 0
#test
{
    const a = 666
    let b = #run a
    GValue = b
    @assert(GValue == 666)
}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("NativeArtifact", "CompilerRunExprInsideTestKeepsJitRunnable");

    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.buildCfg    = "debug";
    cmdLine.backendKind = Runtime::BuildCfgBackendKind::Executable;
    cmdLine.name        = "compiler_run_expr_test";
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    if (compiler.nativeTestFunctions().size() != 1)
        return Result::Error;

    NativeBackendBuilder nativeBuilder(compiler, false);
    if (nativeBuilder.prepare() != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    TaskContext           compilerCtx(compiler);
    const SymbolVariable* globalVar = nullptr;
    for (const SymbolVariable* symbol : nativeBuilder.regularGlobals)
    {
        if (!symbol)
            continue;
        if (symbol->name(compilerCtx) != "GValue")
            continue;

        globalVar = symbol;
        break;
    }

    if (!globalVar || !globalVar->hasGlobalStorage())
        return Result::Error;

    const auto& nativeFunctions = compiler.nativeCodeSegment();
    if (nativeFunctions.empty())
        return Result::Error;

    if (runAfterPauses(compilerCtx, [&] {
            return SymbolFunction::jitBatch(compilerCtx, nativeFunctions);
        }) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const SymbolFunction* const testFn = compiler.nativeTestFunctions().front();
    if (!testFn)
        return Result::Error;
    if (!testFn->jitEntryAddress())
        return Result::Error;

    JITExecManager::Request request;
    request.function     = testFn;
    request.nodeRef      = testFn->declNodeRef();
    request.codeRef      = testFn->decl() ? testFn->decl()->codeRef() : SourceCodeRef::invalid();
    request.runImmediate = true;
    if (compiler.jitExecMgr().submit(compilerCtx, request) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const auto* const globalValue = reinterpret_cast<const int32_t*>(compiler.dataSegmentAddress(globalVar->globalStorageKind(), globalVar->offset()));
    if (!globalValue || *globalValue != 666)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_SilentSpecOpProbeDoesNotDropStructCopyTests)
{
    static constexpr std::string_view SOURCE     = R"(struct Buffer
{
    value: u32
}
impl Buffer
{
    mtd opAffect(text: string)
    {
        .value = cast(u32) @countof(text)
    }
}
#test
{
    var value: Buffer
    value = "abc"
    @assert(value.value == 3)
}
#test
{
    var src: Buffer
    src = "wxyz"
    var dst: Buffer
    dst = src
    @assert(dst.value == 4)
}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("NativeArtifact", "SilentSpecOpProbeDoesNotDropStructCopyTests");

    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.buildCfg    = "debug";
    cmdLine.backendKind = Runtime::BuildCfgBackendKind::Executable;
    cmdLine.name        = "silent_spec_op_probe";
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    if (compiler.nativeTestFunctions().size() != 2)
        return Result::Error;

    NativeBackendBuilder nativeBuilder(compiler, false);
    if (nativeBuilder.prepare() != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (nativeBuilder.testFunctions.size() != 2)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_TestCountMismatchIsReportedBeforeStartupBuild)
{
    static constexpr std::string_view SOURCE     = R"(#test
{
    @assert(true)
}
#test
{
    @assert(true)
}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("NativeArtifact", "TestCountMismatchIsReportedBeforeStartupBuild");

    CommandLine cmdLine = makeStandaloneNativeArtifactCmdLine(ctx, "test_count_mismatch", Runtime::BuildCfgBackendKind::Executable);
    cmdLine.command     = CommandKind::Test;
    cmdLine.files.insert(sourcePath);
    cmdLine.directories.clear();
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    NativeBackendBuilder nativeBuilder(compiler, false);
    if (nativeBuilder.prepare() != Result::Continue)
        return Result::Error;
    if (nativeBuilder.testFunctions.size() != 2)
        return Result::Error;

    nativeBuilder.testFunctions.pop_back();
    nativeBuilder.ctx().setSilentDiagnostic(true);

    const NativeArtifactBuilder artifactBuilder(nativeBuilder);
    if (artifactBuilder.build() != Result::Error)
        return Result::Error;
    if (nativeBuilder.lastErrorId() != DiagnosticId::cmd_err_native_test_count_mismatch)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
