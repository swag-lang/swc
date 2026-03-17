#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Support/Unittest/Unittest.h"

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
            compiler->setupSema(*compilerCtx);
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

        cmdLine.command = CommandKind::Build;
        cmdLine.name    = "native_paths";
        cmdLine.directories.clear();
        cmdLine.files.clear();
        cmdLine.originalDirectories.clear();
        cmdLine.originalFiles.clear();
        cmdLine.modulePath.clear();
        cmdLine.originalModulePath.clear();
        cmdLine.outDir.clear();
        cmdLine.workDir.clear();
        cmdLine.outDirStorage.clear();
        cmdLine.workDirStorage.clear();
        cmdLine.backendKindName = "exe";

        if (!root.empty())
            cmdLine.directories.insert(root);

        CommandLineParser::refreshBuildCfg(cmdLine);
        return cmdLine;
    }

    CommandLine makeStandaloneNativeArtifactCmdLine(const TaskContext& ctx, std::string_view testName, std::string_view artifactKind)
    {
        CommandLine cmdLine     = makeNativeArtifactCmdLine(ctx);
        cmdLine.backendKindName = artifactKind;

        const fs::path tempRoot = Os::getTemporaryPath();
        SWC_ASSERT(!tempRoot.empty());

        const fs::path outputRoot = tempRoot / "swc_unittest" / "native_artifact";
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
        const auto     makeStructBorrowed = ConstantValue::makeStructBorrowed(ctx, compiler.typeMgr().typeString(), bytes);
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

SWC_TEST_BEGIN(NativeArtifact_RDataKeepsOnlyReferencedConstants)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine(ctx, "rdata_keeps_only_referenced_constants", "dll");

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

SWC_TEST_BEGIN(NativeArtifact_RDataKeepsReferencedDependencies)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine(ctx, "rdata_keeps_referenced_dependencies", "dll");

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

    ConstantValue     value   = ConstantValue::makeValuePointer(*fixture.compilerCtx,
                                                                fixture.compiler->typeMgr().typeU8(),
                                                                reinterpret_cast<uint64_t>(rootStorage),
                                                                TypeInfoFlagsE::Const);
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

SWC_TEST_BEGIN(NativeArtifact_StartupCallsRuntimeExitWrapper)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine(ctx, "startup_calls_runtime_exit_wrapper", "exe");

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

SWC_END_NAMESPACE();

#endif
