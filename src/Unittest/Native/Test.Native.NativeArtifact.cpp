#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/JIT/JITExecManager.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeObjFileWriter.h"
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
    Result failNativeArtifactTest(const char* testName, const char* message)
    {
        std::println(stderr, "{}: {}", testName, message);
        return Result::Error;
    }

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

    fs::path inputRootForTest(const CommandLine& cmdLine)
    {
        if (!cmdLine.directories.empty())
            return cmdLine.directories.begin()->lexically_normal();
        if (!cmdLine.files.empty())
            return cmdLine.files.begin()->parent_path().lexically_normal();
        if (!cmdLine.modulePath.empty())
            return cmdLine.modulePath.parent_path().lexically_normal();
        return {};
    }

    fs::path nativeArtifactTestInputRoot()
    {
        return Unittest::makeTestSourcePath("NativeArtifact", "NativePaths").parent_path().lexically_normal();
    }

    CommandLine makeNativeArtifactCmdLine()
    {
        CommandLine cmdLine;
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
        cmdLine.verboseUnittest  = false;
        cmdLine.directories.clear();
        cmdLine.files.clear();
        cmdLine.modulePath.clear();
        cmdLine.outDir.clear();
        cmdLine.workDir.clear();
        cmdLine.outDirStorage.clear();
        cmdLine.workDirStorage.clear();
        cmdLine.backendKind = Runtime::BuildCfgBackendKind::Executable;
        cmdLine.directories.insert(nativeArtifactTestInputRoot());

        CommandLineParser::refreshBuildCfg(cmdLine);
        return cmdLine;
    }

    CommandLine makeStandaloneNativeArtifactCmdLine(std::string_view testName, const Runtime::BuildCfgBackendKind artifactKind)
    {
        CommandLine cmdLine = makeNativeArtifactCmdLine();
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

    std::vector<std::byte> readBinaryFile(const fs::path& path)
    {
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file.is_open())
            return {};

        const std::streamsize fileSize = file.tellg();
        if (fileSize < 0)
            return {};

        std::vector<std::byte> bytes(static_cast<size_t>(fileSize));
        file.seekg(0);
        file.read(reinterpret_cast<char*>(bytes.data()), fileSize);
        if (!file.good())
            return {};

        return bytes;
    }

    template<typename T>
    bool readBinaryRecord(T& outRecord, const std::vector<std::byte>& bytes, size_t offset)
    {
        if (offset > bytes.size() || sizeof(T) > bytes.size() - offset)
            return false;

        std::memcpy(&outRecord, bytes.data() + offset, sizeof(T));
        return true;
    }

    SymbolFunction* makeTestFunction(TaskContext& ctx, std::string_view name)
    {
        auto* function = Symbol::make<SymbolFunction>(ctx, nullptr, TokenRef::invalid(), ctx.idMgr().addIdentifier(name), SymbolFlagsE::Zero);
        function->setReturnTypeRef(ctx.typeMgr().typeVoid());
        function->setTyped(ctx);
        function->setSemaCompleted(ctx);
        return function;
    }

    SymbolVariable* makeTestGlobal(TaskContext& ctx, std::string_view name, const TypeRef typeRef)
    {
        auto* global = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), ctx.idMgr().addIdentifier(name), SymbolFlagsE::Zero);
        global->setTypeRef(typeRef);
        global->setTyped(ctx);
        global->setSemaCompleted(ctx);
        return global;
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

    void rebuildFunctionInfoLookup(NativeBackendBuilder& nativeBuilder)
    {
        nativeBuilder.functionBySymbol.clear();
        for (const auto& info : nativeBuilder.functionInfos)
            nativeBuilder.functionBySymbol.emplace(info.symbol, &info);
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

    template<typename T>
    bool containsPointer(std::span<T* const> values, const T* value)
    {
        return std::ranges::find(values, value) != values.end();
    }

    template<typename T>
    bool hasUniquePointers(std::span<T* const> values)
    {
        std::unordered_set<const T*> seen;
        for (const T* value : values)
        {
            if (!value)
                return false;
            if (!seen.emplace(value).second)
                return false;
        }

        return true;
    }

    SymbolFunction* findFunctionByName(const TaskContext& ctx, std::span<SymbolFunction* const> functions, std::string_view name)
    {
        for (SymbolFunction* function : functions)
        {
            if (function && function->name(ctx) == name)
                return function;
        }

        return nullptr;
    }

    SymbolVariable* findGlobalByName(const TaskContext& ctx, std::span<SymbolVariable* const> globals, std::string_view name)
    {
        for (SymbolVariable* global : globals)
        {
            if (global && global->name(ctx) == name)
                return global;
        }

        return nullptr;
    }
}

SWC_TEST_BEGIN(NativeArtifact_DefaultsToLocalOutputTree)
{
    const CommandLine cmdLine   = makeNativeArtifactCmdLine();
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
    CommandLine                 cmdLine   = makeNativeArtifactCmdLine();
    const fs::path              inputRoot = inputRootForTest(cmdLine);
    CompilerInstance            compiler(ctx.global(), cmdLine);
    NativeBackendBuilder        nativeBuilder(compiler, false);
    const NativeArtifactBuilder artifactBuilder(nativeBuilder);

    if (inputRoot.empty())
        return Result::Error;

    cmdLine.importApiDirs.insert(inputRoot.parent_path().parent_path() / ".output");
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

SWC_FILESYSTEM_TEST_BEGIN(NativeArtifact_RDataKeepsOnlyReferencedConstants)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine("rdata_keeps_only_referenced_constants", Runtime::BuildCfgBackendKind::SharedLibrary);

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

SWC_FILESYSTEM_TEST_BEGIN(NativeArtifact_RDataAllowsInteriorConstantAddresses)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine("rdata_allows_interior_constant_addresses", Runtime::BuildCfgBackendKind::SharedLibrary);

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

SWC_FILESYSTEM_TEST_BEGIN(NativeArtifact_CoffWriterUsesExtendedRelocations)
{
    static constexpr uint32_t RELOCATION_COUNT = 0xFFFF;

    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine("coff_writer_uses_extended_relocations", Runtime::BuildCfgBackendKind::SharedLibrary);
    const NativeArtifactTestFixture fixture(ctx.global(), commandLine);

    MachineCode code;
    code.bytes.resize(sizeof(uint64_t), std::byte{0});
    code.codeRelocations.reserve(RELOCATION_COUNT);
    for (uint32_t relocationIndex = 0; relocationIndex < RELOCATION_COUNT; relocationIndex++)
    {
        code.codeRelocations.push_back({
            .kind          = MicroRelocation::Kind::GlobalInitAddress,
            .codeOffset    = 0,
            .targetAddress = 0,
        });
    }
    addNativeFunctionInfo(*fixture.nativeBuilder, *fixture.compilerCtx, code, "coff_extended_relocations");

    NativeObjDescription description;
    description.objPath = fixture.cmdLine.workDir / "coff_extended_relocations.obj";
    description.functions.push_back(&fixture.nativeBuilder->functionInfos.back());
    fs::create_directories(description.objPath.parent_path());

    const auto objectWriter = NativeObjFileWriter::create(*fixture.nativeBuilder);
    SWC_RESULT(objectWriter->writeObjectFile(description));

    const std::vector<std::byte> objectBytes = readBinaryFile(description.objPath);
    if (objectBytes.empty())
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "object file was not written");

    IMAGE_FILE_HEADER fileHeader{};
    if (!readBinaryRecord(fileHeader, objectBytes, 0))
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "missing file header");
    if (fileHeader.NumberOfSections == 0)
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "missing section header");

    IMAGE_SECTION_HEADER textHeader{};
    if (!readBinaryRecord(textHeader, objectBytes, sizeof(IMAGE_FILE_HEADER)))
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "missing text section header");
    if (std::memcmp(textHeader.Name, ".text", 5) != 0)
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "first section is not .text");
    if (textHeader.NumberOfRelocations != 0xFFFF)
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "section relocation count was not saturated");
    if ((textHeader.Characteristics & IMAGE_SCN_LNK_NRELOC_OVFL) == 0)
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "extended relocation flag is missing");

    IMAGE_RELOCATION overflowRecord{};
    if (!readBinaryRecord(overflowRecord, objectBytes, textHeader.PointerToRelocations))
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "missing overflow relocation record");
    if (overflowRecord.RelocCount != RELOCATION_COUNT + 1)
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "unexpected overflow relocation count");
    if (overflowRecord.SymbolTableIndex != 0 || overflowRecord.Type != 0)
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "overflow relocation record is not empty");

    IMAGE_RELOCATION firstRelocation{};
    if (!readBinaryRecord(firstRelocation, objectBytes, textHeader.PointerToRelocations + sizeof(IMAGE_RELOCATION)))
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "missing first real relocation");
    if (firstRelocation.VirtualAddress != 0 || firstRelocation.Type != IMAGE_REL_AMD64_ADDR64)
        return failNativeArtifactTest("NativeArtifact_CoffWriterUsesExtendedRelocations", "unexpected first relocation payload");
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(NativeArtifact_RDataKeepsReferencedDependencies)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine("rdata_keeps_referenced_dependencies", Runtime::BuildCfgBackendKind::SharedLibrary);

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

    ConstantValue value = ConstantValue::makeValuePointer(*fixture.compilerCtx, fixture.compiler->typeMgr().typeU8(), reinterpret_cast<uint64_t>(rootStorage), TypeInfoFlagsE::Const);
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

SWC_FILESYSTEM_TEST_BEGIN(NativeArtifact_RDataEmitsFunctionRelocations)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine("rdata_emits_function_relocations", Runtime::BuildCfgBackendKind::SharedLibrary);

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

    ConstantValue value = ConstantValue::makeValuePointer(*fixture.compilerCtx, fixture.compiler->typeMgr().typeVoid(), reinterpret_cast<uint64_t>(tableStorage), TypeInfoFlagsE::Const);
    value.setDataSegmentRef({.shardIndex = 0, .offset = tableOffset});
    const ConstantRef rootRef = fixture.compiler->cstMgr().addConstant(*fixture.compilerCtx, value);

    MachineCode ownerCode = makeConstantAddressCode(rootRef, tableStorage);
    addNativeFunctionInfo(*fixture.nativeBuilder, *fixture.compilerCtx, ownerCode, "rdata_owner");

    rebuildFunctionInfoLookup(*fixture.nativeBuilder);

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

SWC_FILESYSTEM_TEST_BEGIN(NativeArtifact_DataEmitsFunctionRelocations)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine("data_emits_function_relocations", Runtime::BuildCfgBackendKind::SharedLibrary);

    const NativeArtifactTestFixture fixture(ctx.global(), commandLine);

    MachineCode targetCode;
    targetCode.bytes.push_back(std::byte{0xC3});

    auto* targetFunction = makeTestFunction(*fixture.compilerCtx, "data_target");
    fixture.nativeBuilder->functionInfos.push_back({
        .symbol      = targetFunction,
        .machineCode = &targetCode,
        .symbolName  = "__test_data_target",
        .debugName   = "data_target",
    });
    rebuildFunctionInfoLookup(*fixture.nativeBuilder);

    DataSegment& initSegment                 = fixture.compiler->globalInitSegment();
    const auto [relocOffset, relocStorage]   = initSegment.reserve<uint64_t>();
    const auto [globalOffset, globalStorage] = initSegment.reserve<uint64_t>();
    *relocStorage                            = 0;
    *globalStorage                           = 0;
    initSegment.addFunctionRelocation(relocOffset, targetFunction);

    auto* global = makeTestGlobal(*fixture.compilerCtx, "GFunctionInit", fixture.compiler->typeMgr().typeU64());
    global->setGlobalStorage(DataSegmentKind::GlobalInit, globalOffset);
    global->setGlobalFunctionInit(targetFunction);
    fixture.nativeBuilder->regularGlobals.push_back(global);

    SWC_RESULT(fixture.artifactBuilder->build());

    if (fixture.nativeBuilder->mergedData.relocations.size() != 2)
        return Result::Error;

    bool foundSegmentRelocation = false;
    bool foundGlobalInitBinding = false;
    for (const NativeSectionRelocation& relocation : fixture.nativeBuilder->mergedData.relocations)
    {
        if (relocation.symbolName != "__test_data_target")
            return Result::Error;
        if (relocation.addend != 0)
            return Result::Error;

        if (relocation.offset == relocOffset)
        {
            foundSegmentRelocation = true;
            continue;
        }

        if (relocation.offset == globalOffset)
        {
            foundGlobalInitBinding = true;
            continue;
        }

        return Result::Error;
    }

    if (!foundSegmentRelocation || !foundGlobalInitBinding)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(NativeArtifact_StartupCallsRuntimeSetupAndCloseWrappers)
{
    const CommandLine commandLine = makeStandaloneNativeArtifactCmdLine("startup_calls_runtime_setup_and_close_wrappers", Runtime::BuildCfgBackendKind::Executable);

    const NativeArtifactTestFixture fixture(ctx.global(), commandLine);

    auto* mainFunction         = makeTestFunction(*fixture.compilerCtx, "main");
    auto* setupRuntimeFunction = makeTestFunction(*fixture.compilerCtx, "__setupRuntime");
    auto* closeRuntimeFunction = makeTestFunction(*fixture.compilerCtx, "__closeRuntime");
    fixture.compiler->registerRuntimeFunctionSymbol(fixture.compilerCtx->idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::SetupRuntime), setupRuntimeFunction);
    fixture.compiler->registerRuntimeFunctionSymbol(fixture.compilerCtx->idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::CloseRuntime), closeRuntimeFunction);
    fixture.nativeBuilder->mainFunctions.push_back(mainFunction);

    SWC_RESULT(fixture.artifactBuilder->build());

    if (!fixture.nativeBuilder->startup)
        return Result::Error;

    bool foundSetupRelocation = false;
    bool foundCloseRelocation = false;
    for (const auto& relocation : fixture.nativeBuilder->startup->code.codeRelocations)
    {
        if (relocation.targetSymbol == setupRuntimeFunction)
        {
            if (relocation.kind != MicroRelocation::Kind::LocalFunctionAddress)
                return Result::Error;

            foundSetupRelocation = true;
            continue;
        }

        if (relocation.targetSymbol != closeRuntimeFunction)
            continue;

        if (relocation.kind != MicroRelocation::Kind::LocalFunctionAddress)
            return Result::Error;

        foundCloseRelocation = true;
    }

    if (!foundSetupRelocation || !foundCloseRelocation)
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
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "errors after sema");

    if (compiler.nativeTestFunctions().size() != 1)
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "unexpected native test function count");

    NativeBackendBuilder nativeBuilder(compiler, false);
    if (nativeBuilder.prepare() != Result::Continue)
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "nativeBuilder.prepare failed");
    if (Stats::getNumErrors() != errorsBefore)
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "errors after nativeBuilder.prepare");

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
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "global GValue not found");

    const auto& nativeFunctions = compiler.nativeCodeSegment();
    if (nativeFunctions.empty())
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "native code segment empty");

    while (true)
    {
        const Result jitBatchResult = SymbolFunction::jitBatch(compilerCtx, nativeFunctions);
        if (jitBatchResult == Result::Continue)
            break;

        if (jitBatchResult == Result::Error)
            return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "jitBatch returned error");

        Sema::waitDone(compilerCtx, compilerCtx.compiler().jobClientId());
        if (Stats::hasError())
            return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "jitBatch wait reported stats error");
        if (compilerCtx.state().jitEmissionError)
            return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "jitBatch wait reported jit emission error");
    }
    if (Stats::getNumErrors() != errorsBefore)
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "errors after jitBatch");

    const SymbolFunction* testFn = compiler.nativeTestFunctions().front();
    if (!testFn)
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "missing native test function");
    if (!testFn->jitEntryAddress())
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "native test function has no jit entry");

    JITExecManager::Request request;
    request.function     = testFn;
    request.nodeRef      = testFn->declNodeRef();
    request.codeRef      = testFn->decl() ? testFn->decl()->codeRef() : SourceCodeRef::invalid();
    request.runImmediate = true;
    if (compiler.jitExecMgr().submit(compilerCtx, request) != Result::Continue)
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "jit submit failed");
    if (Stats::getNumErrors() != errorsBefore)
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "errors after jit submit");

    const auto* globalValue = reinterpret_cast<const int32_t*>(compiler.dataSegmentAddress(globalVar->globalStorageKind(), globalVar->offset()));
    if (!globalValue || *globalValue != 666)
        return failNativeArtifactTest("NativeArtifact_CompilerRunExprInsideTestKeepsJitRunnable", "unexpected final GValue");
}
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent)
{
    static constexpr std::string_view SOURCE     = R"(#global fileprivate

alias UnaryFn = func(s32)->s32

func addOne(value: s32)->s32
{
    return value + 1
}

var GAddOne: UnaryFn = &addOne

#init
{
}

#premain
{
}

#test
{
    @assert(GAddOne(41) == 42)
}

#main
{
}

#drop
{
}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("NativeArtifact", "CompilerInstanceNativeRegistrationKeepsBucketsConsistent");

    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.buildCfg    = "debug";
    cmdLine.backendKind = Runtime::BuildCfgBackendKind::Executable;
    cmdLine.name        = "compiler_instance_native_registration";
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "errors after sema");

    const TaskContext compilerCtx(compiler);

    const auto initTargets = compiler.nativeGlobalFunctionInitTargetsSnapshot();
    if (compiler.nativeTestFunctions().size() != 1)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "unexpected native test function count");
    if (compiler.nativeInitFunctions().size() != 1)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "unexpected native init function count");
    if (compiler.nativePreMainFunctions().size() != 1)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "unexpected native premain function count");
    if (compiler.nativeMainFunctions().size() != 1)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "unexpected native main function count");
    if (compiler.nativeDropFunctions().size() != 1)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "unexpected native drop function count");
    if (initTargets.size() != 1)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "unexpected native global init target count");

    SymbolFunction* addOneFunction = findFunctionByName(compilerCtx, initTargets, "addOne");
    if (!addOneFunction)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "addOne not found in native init targets");

    SymbolVariable* globalFunctionPtr = findGlobalByName(compilerCtx, compiler.nativeGlobalVariables(), "GAddOne");
    if (!globalFunctionPtr)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "GAddOne global not found");
    if (globalFunctionPtr->globalFunctionInit() != addOneFunction)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "GAddOne global init target mismatch");
    if (initTargets.front() != addOneFunction)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native init target mismatch");

    if (!hasUniquePointers(std::span{compiler.nativeCodeSegment()}))
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native code segment contains duplicates");
    if (!containsPointer(std::span{compiler.nativeCodeSegment()}, compiler.nativeTestFunctions().front()))
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native code segment missing test function");
    if (!containsPointer(std::span{compiler.nativeCodeSegment()}, compiler.nativeInitFunctions().front()))
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native code segment missing init function");
    if (!containsPointer(std::span{compiler.nativeCodeSegment()}, compiler.nativePreMainFunctions().front()))
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native code segment missing premain function");
    if (!containsPointer(std::span{compiler.nativeCodeSegment()}, compiler.nativeMainFunctions().front()))
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native code segment missing main function");
    if (!containsPointer(std::span{compiler.nativeCodeSegment()}, compiler.nativeDropFunctions().front()))
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native code segment missing drop function");

    const size_t          codeCount                  = compiler.nativeCodeSegment().size();
    const size_t          testCount                  = compiler.nativeTestFunctions().size();
    const size_t          initCount                  = compiler.nativeInitFunctions().size();
    const size_t          preMainCount               = compiler.nativePreMainFunctions().size();
    const size_t          mainCount                  = compiler.nativeMainFunctions().size();
    const size_t          dropCount                  = compiler.nativeDropFunctions().size();
    const size_t          globalVariableCount        = compiler.nativeGlobalVariables().size();
    const size_t          initTargetCount            = initTargets.size();
    const auto            preparedJitFunctionsBefore = compiler.jitPreparedFunctionsSnapshot();
    const size_t          preparedJitCount           = preparedJitFunctionsBefore.size();
    const size_t          preparedJitTargetCount     = std::ranges::count(preparedJitFunctionsBefore, addOneFunction);
    const uint64_t        initTargetVersion          = compiler.nativeGlobalFunctionInitTargetsVersion();
    SymbolFunction* const codeFunction               = compiler.nativeCodeSegment().front();
    SymbolFunction* const testFunction               = compiler.nativeTestFunctions().front();
    SymbolFunction* const initFunction               = compiler.nativeInitFunctions().front();
    SymbolFunction* const preMainFunction            = compiler.nativePreMainFunctions().front();
    SymbolFunction* const mainFunction               = compiler.nativeMainFunctions().front();
    SymbolFunction* const dropFunction               = compiler.nativeDropFunctions().front();

    compiler.registerNativeCodeFunction(codeFunction);
    compiler.registerNativeTestFunction(testFunction);
    compiler.registerNativeInitFunction(initFunction);
    compiler.registerNativePreMainFunction(preMainFunction);
    compiler.registerNativeMainFunction(mainFunction);
    compiler.registerNativeDropFunction(dropFunction);
    compiler.registerNativeGlobalVariable(globalFunctionPtr);
    compiler.registerNativeGlobalFunctionInitTarget(addOneFunction);
    compiler.registerPreparedJitFunction(addOneFunction);
    compiler.registerPreparedJitFunction(addOneFunction);

    if (compiler.nativeCodeSegment().size() != codeCount)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native code segment changed after duplicate registration");
    if (compiler.nativeTestFunctions().size() != testCount)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native test functions changed after duplicate registration");
    if (compiler.nativeInitFunctions().size() != initCount)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native init functions changed after duplicate registration");
    if (compiler.nativePreMainFunctions().size() != preMainCount)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native premain functions changed after duplicate registration");
    if (compiler.nativeMainFunctions().size() != mainCount)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native main functions changed after duplicate registration");
    if (compiler.nativeDropFunctions().size() != dropCount)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native drop functions changed after duplicate registration");
    if (compiler.nativeGlobalVariables().size() != globalVariableCount)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native globals changed after duplicate registration");
    if (compiler.nativeGlobalFunctionInitTargetsSnapshot().size() != initTargetCount)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native init targets changed after duplicate registration");
    if (compiler.nativeGlobalFunctionInitTargetsVersion() != initTargetVersion)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "native init target version changed after duplicate registration");

    const auto jitPreparedFunctions = compiler.jitPreparedFunctionsSnapshot();
    if (jitPreparedFunctions.size() != preparedJitCount + (preparedJitTargetCount ? 0u : 1u))
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "unexpected prepared jit function growth");
    if (std::ranges::count(jitPreparedFunctions, addOneFunction) != 1)
        return failNativeArtifactTest("NativeArtifact_CompilerInstanceNativeRegistrationKeepsBucketsConsistent", "prepared jit function target duplicated");

    return Result::Continue;
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
    mtd opSet(text: string)
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

SWC_END_NAMESPACE();

#endif
