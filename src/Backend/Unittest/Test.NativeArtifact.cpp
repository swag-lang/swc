#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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
}

SWC_TEST_BEGIN(NativeArtifact_DefaultsToLocalOutputTree)
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
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_RDataKeepsOnlyReferencedConstants)
CommandLine cmdLine     = makeNativeArtifactCmdLine(ctx);
cmdLine.backendKindName = "dll";
CommandLineParser::refreshBuildCfg(cmdLine);

CompilerInstance compiler(ctx.global(), cmdLine);
TaskContext      compilerCtx(compiler);
compiler.setupSema(compilerCtx);
NativeBackendBuilder        nativeBuilder(compiler, false);
const NativeArtifactBuilder artifactBuilder(nativeBuilder);

constexpr auto referencedMarker   = "__native_rdata_referenced_marker__";
constexpr auto unreferencedMarker = "__native_rdata_unreferenced_marker__";

DataSegment& segment = compiler.cstMgr().shardDataSegment(0);

const auto [referencedStringView, referencedStringOffset]     = segment.addString(referencedMarker);
const auto [unreferencedStringView, unreferencedStringOffset] = segment.addString(unreferencedMarker);

const auto [referencedRuntimeStringOffset, referencedRuntimeStringStorage] = segment.reserve<Runtime::String>();
referencedRuntimeStringStorage->ptr                                        = referencedStringView.data();
referencedRuntimeStringStorage->length                                     = referencedStringView.size();
segment.addRelocation(referencedRuntimeStringOffset + offsetof(Runtime::String, ptr), referencedStringOffset);

const auto [unreferencedRuntimeStringOffset, unreferencedRuntimeStringStorage] = segment.reserve<Runtime::String>();
unreferencedRuntimeStringStorage->ptr                                          = unreferencedStringView.data();
unreferencedRuntimeStringStorage->length                                       = unreferencedStringView.size();
segment.addRelocation(unreferencedRuntimeStringOffset + offsetof(Runtime::String, ptr), unreferencedStringOffset);

const ConstantRef referencedStringRef = compiler.cstMgr().addConstant(compilerCtx,
                                                                      ConstantValue::makeStructBorrowed(compilerCtx,
                                                                                                        compiler.typeMgr().typeString(),
                                                                                                        ByteSpan{reinterpret_cast<const std::byte*>(referencedRuntimeStringStorage), sizeof(Runtime::String)}));
SWC_UNUSED(compiler.cstMgr().addConstant(compilerCtx,
                                         ConstantValue::makeStructBorrowed(compilerCtx,
                                                                           compiler.typeMgr().typeString(),
                                                                           ByteSpan{reinterpret_cast<const std::byte*>(unreferencedRuntimeStringStorage), sizeof(Runtime::String)})));

MachineCode code;
code.bytes.resize(sizeof(uint64_t));
code.codeRelocations.push_back({
    .kind          = MicroRelocation::Kind::ConstantAddress,
    .codeOffset    = 0,
    .targetAddress = reinterpret_cast<uint64_t>(referencedRuntimeStringStorage),
    .constantRef   = referencedStringRef,
});

nativeBuilder.functionInfos.push_back({
    .symbol      = makeTestFunction(compilerCtx, "rdata_referenced"),
    .machineCode = &code,
    .symbolName  = "__test_rdata_referenced",
    .debugName   = "rdata_referenced",
});

SWC_RESULT(artifactBuilder.build());

if (!containsBytes(nativeBuilder.mergedRData.bytes, referencedMarker))
    return Result::Error;
if (containsBytes(nativeBuilder.mergedRData.bytes, unreferencedMarker))
    return Result::Error;
if (nativeBuilder.mergedRData.relocations.size() != 1)
    return Result::Error;
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_RDataKeepsReferencedDependencies)
CommandLine cmdLine     = makeNativeArtifactCmdLine(ctx);
cmdLine.backendKindName = "dll";
CommandLineParser::refreshBuildCfg(cmdLine);

CompilerInstance compiler(ctx.global(), cmdLine);
TaskContext      compilerCtx(compiler);
compiler.setupSema(compilerCtx);
NativeBackendBuilder        nativeBuilder(compiler, false);
const NativeArtifactBuilder artifactBuilder(nativeBuilder);

constexpr auto dependencyMarker = "__native_rdata_dependency_marker__";

DataSegment& segment                     = compiler.cstMgr().shardDataSegment(0);
const auto [stringView, stringOffset]    = segment.addString(dependencyMarker);
const auto [nestedOffset, nestedStorage] = segment.reserve<uint64_t>();
*nestedStorage                           = reinterpret_cast<uint64_t>(stringView.data());
segment.addRelocation(nestedOffset, stringOffset);

const auto [rootOffset, rootStorage] = segment.reserve<uint64_t>();
*rootStorage                         = reinterpret_cast<uint64_t>(nestedStorage);
segment.addRelocation(rootOffset, nestedOffset);

const ConstantRef rootRef = compiler.cstMgr().addConstant(compilerCtx,
                                                          ConstantValue::makeValuePointer(compilerCtx,
                                                                                          compiler.typeMgr().typeU8(),
                                                                                          reinterpret_cast<uint64_t>(rootStorage),
                                                                                          TypeInfoFlagsE::Const));

MachineCode code;
code.bytes.resize(sizeof(uint64_t));
code.codeRelocations.push_back({
    .kind          = MicroRelocation::Kind::ConstantAddress,
    .codeOffset    = 0,
    .targetAddress = reinterpret_cast<uint64_t>(rootStorage),
    .constantRef   = rootRef,
});

nativeBuilder.functionInfos.push_back({
    .symbol      = makeTestFunction(compilerCtx, "rdata_dependency"),
    .machineCode = &code,
    .symbolName  = "__test_rdata_dependency",
    .debugName   = "rdata_dependency",
});

SWC_RESULT(artifactBuilder.build());

if (!containsBytes(nativeBuilder.mergedRData.bytes, dependencyMarker))
    return Result::Error;
if (nativeBuilder.mergedRData.relocations.size() != 2)
    return Result::Error;

uint32_t emittedRootOffset   = 0;
uint32_t emittedNestedOffset = 0;
uint32_t emittedStringOffset = 0;
if (!nativeBuilder.tryMapRDataSourceOffset(emittedRootOffset, 0, rootOffset))
    return Result::Error;
if (!nativeBuilder.tryMapRDataSourceOffset(emittedNestedOffset, 0, nestedOffset))
    return Result::Error;
if (!nativeBuilder.tryMapRDataSourceOffset(emittedStringOffset, 0, stringOffset))
    return Result::Error;
if (emittedRootOffset == emittedNestedOffset || emittedNestedOffset == emittedStringOffset)
    return Result::Error;
SWC_TEST_END()

SWC_TEST_BEGIN(NativeArtifact_StartupCallsRuntimeExitWrapper)
CommandLine cmdLine     = makeNativeArtifactCmdLine(ctx);
cmdLine.backendKindName = "exe";
CommandLineParser::refreshBuildCfg(cmdLine);

CompilerInstance compiler(ctx.global(), cmdLine);
TaskContext      compilerCtx(compiler);
compiler.setupSema(compilerCtx);
NativeBackendBuilder        nativeBuilder(compiler, false);
const NativeArtifactBuilder artifactBuilder(nativeBuilder);

auto* mainFunction = makeTestFunction(compilerCtx, "main");
auto* exitFunction = makeTestFunction(compilerCtx, "__exit");
compiler.registerRuntimeFunctionSymbol(compilerCtx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::Exit), exitFunction);
nativeBuilder.mainFunctions.push_back(mainFunction);

SWC_RESULT(artifactBuilder.build());

if (!nativeBuilder.startup)
    return Result::Error;

bool foundExitRelocation = false;
for (const auto& relocation : nativeBuilder.startup->code.codeRelocations)
{
    if (relocation.targetSymbol != exitFunction)
        continue;

    if (relocation.kind != MicroRelocation::Kind::LocalFunctionAddress)
        return Result::Error;

    foundExitRelocation = true;
}

if (!foundExitRelocation)
    return Result::Error;
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
