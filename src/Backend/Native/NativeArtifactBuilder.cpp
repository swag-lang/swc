#include "pch.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/ABI/ABICall.h"
#include "Main/CommandLineParser.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Math/Helpers.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view K_NATIVE_TEMP_FOLDER = "swc_native";

    Utf8 runtimeStringToUtf8(const Runtime::String& value)
    {
        if (!value.ptr || !value.length)
            return {};

        return {std::string_view(value.ptr, value.length)};
    }

    Utf8 objectFileName(const Utf8& baseName, const uint32_t objectIndex)
    {
        return std::format("{}_{:02}.obj", baseName, objectIndex);
    }
}

NativeArtifactBuilder::NativeArtifactBuilder(NativeBackendBuilder& builder) :
    builder_(builder)
{
}

void NativeArtifactBuilder::queryPaths(NativeArtifactPaths& outPaths, const std::optional<uint32_t> workDirIndex, const uint32_t numObjects) const
{
    outPaths.workDir.clear();
    outPaths.objectPaths.clear();
    outPaths.baseName        = artifactBaseName();
    outPaths.workDirRootName = configuredWorkDirectoryName();
    if (outPaths.workDirRootName.empty())
        outPaths.workDirRootName = automaticWorkDirectoryName(outPaths.baseName);

    outPaths.workDirRoot       = Os::getTemporaryPath() / K_NATIVE_TEMP_FOLDER / outPaths.workDirRootName.c_str();
    outPaths.artifactExtension = artifactExtension();
    outPaths.artifactOutputDir = configuredArtifactOutputDirectory(outPaths.workDirRoot);
    outPaths.artifactPath      = outPaths.artifactOutputDir / std::format("{}{}", outPaths.baseName, outPaths.artifactExtension);

    if (!workDirIndex.has_value())
        return;

    outPaths.workDir = workDirectory(outPaths.workDirRoot, workDirIndex.value());
    outPaths.objectPaths.clear();
    outPaths.objectPaths.reserve(numObjects);
    for (uint32_t i = 0; i < numObjects; ++i)
        outPaths.objectPaths.push_back(outPaths.workDir / objectFileName(outPaths.baseName, i).c_str());
}

Result NativeArtifactBuilder::build() const
{
    SWC_RESULT_VERIFY(validateNativeData());
    SWC_RESULT_VERIFY(prepareDataSections());
    SWC_RESULT_VERIFY(buildStartup());
    return partitionObjects();
}

Result NativeArtifactBuilder::validateNativeData() const
{
    const auto& compiler = builder_.compiler();

    if (compiler.compilerSegment().size() != 0)
        return builder_.reportError(DiagnosticId::cmd_err_native_compiler_segment_unsupported);
    if (compiler.constantSegment().size() != 0)
        return builder_.reportError(DiagnosticId::cmd_err_native_constant_segment_unsupported);
    if (!compiler.globalZeroSegment().relocations().empty())
        return builder_.reportError(DiagnosticId::cmd_err_native_global_zero_relocations_unsupported);
    if (!compiler.globalInitSegment().relocations().empty())
        return builder_.reportError(DiagnosticId::cmd_err_native_global_init_relocations_unsupported);

    for (const SymbolVariable* symbol : builder_.regularGlobals)
    {
        if (!symbol)
            continue;
        if (symbol->globalStorageKind() == DataSegmentKind::Compiler)
            return builder_.reportError(DiagnosticId::cmd_err_native_compiler_global_unsupported, Diagnostic::ARG_SYM, symbol->getFullScopedName(builder_.ctx()));
        if (symbol->globalStorageKind() != DataSegmentKind::GlobalInit)
            continue;
        if (symbol->hasExtraFlag(SymbolVariableFlagsE::ExplicitUndefined))
            return builder_.reportError(DiagnosticId::cmd_err_native_undefined_global_unsupported, Diagnostic::ARG_SYM, symbol->getFullScopedName(builder_.ctx()));
        if (!symbol->cstRef().isValid())
            continue;
        if (!isNativeStaticType(symbol->typeRef()))
            return builder_.reportError(DiagnosticId::cmd_err_native_static_data_unsupported, Diagnostic::ARG_SYM, symbol->getFullScopedName(builder_.ctx()));
    }

    for (const auto& info : builder_.functionInfos)
    {
        SWC_RESULT_VERIFY(validateRelocations(*info.symbol, *info.machineCode));
    }

    return Result::Continue;
}

bool NativeArtifactBuilder::isNativeStaticType(const TypeRef typeRef) const
{
    if (typeRef.isInvalid())
        return false;

    const TypeInfo& typeInfo = builder_.ctx().typeMgr().get(typeRef);
    if (typeInfo.isAlias())
    {
        const TypeRef unwrapped = typeInfo.unwrap(builder_.ctx(), typeRef, TypeExpandE::Alias);
        return unwrapped.isValid() && isNativeStaticType(unwrapped);
    }

    if (typeInfo.isEnum())
        return isNativeStaticType(typeInfo.payloadSymEnum().underlyingTypeRef());

    if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat())
        return true;

    if (typeInfo.isArray())
        return isNativeStaticType(typeInfo.payloadArrayElemTypeRef());

    if (typeInfo.isAggregate())
    {
        for (const TypeRef child : typeInfo.payloadAggregate().types)
        {
            if (!isNativeStaticType(child))
                return false;
        }

        return true;
    }

    if (typeInfo.isStruct())
    {
        for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
        {
            if (field && !isNativeStaticType(field->typeRef()))
                return false;
        }

        return true;
    }

    if (typeInfo.isPointerLike() || typeInfo.isReference() || typeInfo.isVariadic() || typeInfo.isTypedVariadic())
        return false;

    return false;
}

Result NativeArtifactBuilder::validateRelocations(const SymbolFunction& owner, const MachineCode& code) const
{
    for (const auto& relocation : code.codeRelocations)
    {
        switch (relocation.kind)
        {
            case MicroRelocation::Kind::CompilerAddress:
                return builder_.reportError(DiagnosticId::cmd_err_native_function_uses_compiler_data, Diagnostic::ARG_SYM, owner.getFullScopedName(builder_.ctx()));

            case MicroRelocation::Kind::LocalFunctionAddress:
            {
                const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
                if (!target)
                    return builder_.reportError(DiagnosticId::cmd_err_native_invalid_local_function_relocation, Diagnostic::ARG_SYM, owner.getFullScopedName(builder_.ctx()));
                if (!builder_.functionBySymbol.contains(const_cast<SymbolFunction*>(target)))
                    return builder_.reportError(DiagnosticId::cmd_err_native_unsupported_local_function, Diagnostic::ARG_SYM, owner.getFullScopedName(builder_.ctx()), Diagnostic::ARG_TARGET, target->getFullScopedName(builder_.ctx()));
                break;
            }

            case MicroRelocation::Kind::ForeignFunctionAddress:
            {
                const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
                if (!target || !target->isForeign())
                    return builder_.reportError(DiagnosticId::cmd_err_native_invalid_foreign_function_relocation, Diagnostic::ARG_SYM, owner.getFullScopedName(builder_.ctx()));
                break;
            }

            case MicroRelocation::Kind::GlobalZeroAddress:
                if (builder_.compiler().globalZeroSegment().size() == 0)
                    return builder_.reportError(DiagnosticId::cmd_err_native_empty_global_zero_segment, Diagnostic::ARG_SYM, owner.getFullScopedName(builder_.ctx()));
                break;

            case MicroRelocation::Kind::GlobalInitAddress:
                if (builder_.compiler().globalInitSegment().size() == 0)
                    return builder_.reportError(DiagnosticId::cmd_err_native_empty_global_init_segment, Diagnostic::ARG_SYM, owner.getFullScopedName(builder_.ctx()));
                break;

            case MicroRelocation::Kind::ConstantAddress:
            {
                uint32_t  shardIndex = 0;
                const Ref ref        = builder_.compiler().cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(relocation.targetAddress));
                if (ref == INVALID_REF)
                    return builder_.reportError(DiagnosticId::cmd_err_native_constant_storage_unsupported, Diagnostic::ARG_SYM, owner.getFullScopedName(builder_.ctx()));
                if (!validateConstantRelocation(relocation))
                    return builder_.reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, owner.getFullScopedName(builder_.ctx()));
                break;
            }
        }
    }

    return Result::Continue;
}

bool NativeArtifactBuilder::validateConstantRelocation(const MicroRelocation& relocation) const
{
    if (!relocation.constantRef.isValid())
        return false;

    const ConstantValue& constant = builder_.compiler().cstMgr().get(relocation.constantRef);
    switch (constant.kind())
    {
        case ConstantKind::Struct:
            return relocation.targetAddress == reinterpret_cast<uint64_t>(constant.getStruct().data()) && isNativeStaticType(constant.typeRef());

        case ConstantKind::Array:
            return relocation.targetAddress == reinterpret_cast<uint64_t>(constant.getArray().data()) && isNativeStaticType(constant.typeRef());

        case ConstantKind::ValuePointer:
        case ConstantKind::BlockPointer:
        {
            uint32_t shardIndex = 0;
            return builder_.compiler().cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(relocation.targetAddress)) != INVALID_REF;
        }

        case ConstantKind::Null:
            return true;

        default:
            return false;
    }
}

Result NativeArtifactBuilder::prepareDataSections() const
{
    builder_.mergedRData.name            = ".rdata";
    builder_.mergedRData.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_ALIGN_16BYTES;
    builder_.mergedData.name             = ".data";
    builder_.mergedData.characteristics  = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;
    builder_.mergedBss.name              = ".bss";
    builder_.mergedBss.characteristics   = IMAGE_SCN_CNT_UNINITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;

    builder_.mergedRData.bytes.clear();
    builder_.mergedRData.relocations.clear();
    builder_.mergedData.bytes.clear();
    builder_.mergedData.relocations.clear();
    builder_.mergedBss.bssSize = builder_.compiler().globalZeroSegment().size();
    builder_.mergedBss.bss     = builder_.mergedBss.bssSize != 0;
    builder_.rdataShardBaseOffsets.fill(0);

    for (uint32_t shardIndex = 0; shardIndex < ConstantManager::SHARD_COUNT; ++shardIndex)
    {
        const DataSegment& segment     = builder_.compiler().cstMgr().shardDataSegment(shardIndex);
        const uint32_t     segmentSize = segment.size();
        if (!segmentSize)
            continue;

        const uint32_t baseOffset = Math::alignUpU32(static_cast<uint32_t>(builder_.mergedRData.bytes.size()), 16);
        if (builder_.mergedRData.bytes.size() < baseOffset)
            builder_.mergedRData.bytes.resize(baseOffset, std::byte{0});
        builder_.rdataShardBaseOffsets[shardIndex] = baseOffset;

        const uint32_t insertOffset = static_cast<uint32_t>(builder_.mergedRData.bytes.size());
        builder_.mergedRData.bytes.resize(insertOffset + segmentSize);
        segment.copyTo(ByteSpanRW{builder_.mergedRData.bytes.data() + insertOffset, segmentSize});

        for (const auto& relocation : segment.relocations())
        {
            NativeSectionRelocation record;
            record.offset     = baseOffset + relocation.offset;
            record.symbolName = K_R_DATA_BASE_SYMBOL;
            record.addend     = baseOffset + relocation.targetOffset;
            builder_.mergedRData.relocations.push_back(record);
        }
    }

    const uint32_t dataSize = builder_.compiler().globalInitSegment().size();
    if (dataSize)
    {
        builder_.mergedData.bytes.resize(dataSize);
        builder_.compiler().globalInitSegment().copyTo(ByteSpanRW{builder_.mergedData.bytes.data(), dataSize});
    }

    return Result::Continue;
}

Result NativeArtifactBuilder::buildStartup() const
{
    builder_.startup.reset();

    if (builder_.compiler().buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable)
        return Result::Continue;

    auto         startup = std::make_unique<NativeStartupInfo>();
    MicroBuilder builder(builder_.ctx());
    builder.setBackendBuildCfg(builder_.compiler().buildCfg().backend);

    for (SymbolFunction* symbol : builder_.compiler().nativeInitFunctions())
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_.compiler().nativePreMainFunctions())
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_.compiler().nativeTestFunctions())
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_.compiler().nativeDropFunctions())
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});

    auto* exitProcess = Symbol::make<SymbolFunction>(builder_.ctx(), nullptr, TokenRef::invalid(), builder_.compiler().idMgr().addIdentifier("ExitProcess"), SymbolFlagsE::Zero);
    exitProcess->attributes().setForeign("kernel32", "ExitProcess");
    exitProcess->setCallConvKind(CallConvKind::Host);
    exitProcess->setReturnTypeRef(builder_.compiler().typeMgr().typeVoid());

    SmallVector<ABICall::PreparedArg> exitArgs;
    exitArgs.push_back({
        .srcReg      = CallConv::host().intReturn,
        .kind        = ABICall::PreparedArgKind::Direct,
        .isFloat     = false,
        .isAddressed = false,
        .numBits     = 32,
    });

    builder.emitClearReg(CallConv::host().intReturn, MicroOpBits::B32);
    const ABICall::PreparedCall preparedExit = ABICall::prepareArgs(builder, CallConvKind::Host, exitArgs.span());
    ABICall::callExtern(builder, CallConvKind::Host, exitProcess, preparedExit);
    builder.emitRet();

    if (startup->code.emit(builder_.ctx(), builder) != Result::Continue)
        return builder_.reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

    builder_.startup = std::move(startup);
    return Result::Continue;
}

Result NativeArtifactBuilder::partitionObjects() const
{
    builder_.objectDescriptions.clear();

    const size_t functionCount = builder_.functionInfos.size();
    uint32_t     maxJobs       = builder_.ctx().cmdLine().numCores;
    if (!maxJobs)
        maxJobs = std::max<uint32_t>(1, builder_.ctx().global().jobMgr().numWorkers());
    if (!maxJobs)
        maxJobs = 1;

    const uint32_t numJobs = std::max<uint32_t>(1, static_cast<uint32_t>(functionCount ? std::min<size_t>(functionCount, maxJobs) : 1));
    builder_.objectDescriptions.resize(numJobs);

    const uint32_t      workDirIndex = builder_.compiler().atomicId().fetch_add(1, std::memory_order_relaxed);
    NativeArtifactPaths paths;
    queryPaths(paths, workDirIndex, numJobs);
    SWC_RESULT_VERIFY(createWorkDirectory(paths.workDir));
    SWC_RESULT_VERIFY(createArtifactOutputDirectory(paths.artifactOutputDir));
    builder_.workDir      = paths.workDir;
    builder_.artifactPath = paths.artifactPath;

    for (uint32_t i = 0; i < numJobs; ++i)
    {
        builder_.objectDescriptions[i].index       = i;
        builder_.objectDescriptions[i].includeData = i == 0;
        builder_.objectDescriptions[i].objPath     = paths.objectPaths[i];
    }

    if (builder_.startup)
        builder_.objectDescriptions[0].startup = builder_.startup.get();

    for (size_t i = 0; i < builder_.functionInfos.size(); ++i)
    {
        NativeFunctionInfo& info     = builder_.functionInfos[i];
        const uint32_t      objIndex = static_cast<uint32_t>(i % numJobs);
        info.jobIndex                = objIndex;
        builder_.objectDescriptions[objIndex].functions.push_back(&info);
    }
    return Result::Continue;
}

Utf8 NativeArtifactBuilder::configuredArtifactBaseName() const
{
    const Utf8 buildCfgName = runtimeStringToUtf8(builder_.compiler().buildCfg().nativeArtifactBaseName);
    if (!buildCfgName.empty())
        return FileSystem::sanitizeFileName(buildCfgName);

    return {};
}

Utf8 NativeArtifactBuilder::artifactBaseName() const
{
    Utf8 configuredName = configuredArtifactBaseName();
    if (!configuredName.empty())
        return configuredName;

    const auto& cmdLine = builder_.ctx().cmdLine();

    if (!cmdLine.modulePath.empty())
        return FileSystem::sanitizeFileName(Utf8(cmdLine.modulePath.filename().string()));
    if (cmdLine.files.size() == 1)
        return FileSystem::sanitizeFileName(Utf8(cmdLine.files.begin()->stem().string()));
    if (cmdLine.directories.size() == 1)
        return FileSystem::sanitizeFileName(Utf8(cmdLine.directories.begin()->filename().string()));
    return "native_test";
}

Utf8 NativeArtifactBuilder::artifactExtension() const
{
    switch (builder_.ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            switch (builder_.compiler().buildCfg().backendKind)
            {
                case Runtime::BuildCfgBackendKind::Executable:
                    return ".exe";
                case Runtime::BuildCfgBackendKind::Library:
                    return ".dll";
                case Runtime::BuildCfgBackendKind::Export:
                    return ".lib";
                case Runtime::BuildCfgBackendKind::None:
                    break;
            }

            break;
    }

    SWC_UNREACHABLE();
}

fs::path NativeArtifactBuilder::configuredArtifactOutputDirectory(const fs::path& defaultOutputDir) const
{
    const Utf8 buildCfgDir = runtimeStringToUtf8(builder_.compiler().buildCfg().nativeArtifactOutputDir);
    if (!buildCfgDir.empty())
        return {buildCfgDir.c_str()};
    return defaultOutputDir;
}

Result NativeArtifactBuilder::createArtifactOutputDirectory(const fs::path& outputDir) const
{
    std::error_code ec;
    fs::create_directories(outputDir, ec);
    if (ec)
        return builder_.reportError(DiagnosticId::cmd_err_native_work_dir_create_failed, Diagnostic::ARG_PATH, FileSystem::toUtf8Path(outputDir), Diagnostic::ARG_BECAUSE, ec.message());
    return Result::Continue;
}

Utf8 NativeArtifactBuilder::configuredWorkDirectoryName() const
{
    const Utf8 buildCfgName = runtimeStringToUtf8(builder_.compiler().buildCfg().nativeWorkDirName);
    if (!buildCfgName.empty())
        return FileSystem::sanitizeFileName(buildCfgName);

    return {};
}

Utf8 NativeArtifactBuilder::automaticWorkDirectoryName(const Utf8& baseName) const
{
    const CommandLine& cmdLine = builder_.ctx().cmdLine();
    Utf8               key;

    key += std::format("cmd={};os={};arch={};backend={};sub={};base={};", static_cast<int>(cmdLine.command), static_cast<int>(cmdLine.targetOs), static_cast<int>(cmdLine.targetArch), static_cast<int>(builder_.compiler().buildCfg().backendKind), static_cast<int>(builder_.compiler().buildCfg().backendSubKind), baseName);

    if (!cmdLine.modulePath.empty())
    {
        key += "module=";
        key += FileSystem::toUtf8Path(cmdLine.modulePath);
        key += ";";
    }

    for (const fs::path& file : cmdLine.files)
    {
        key += "file=";
        key += FileSystem::toUtf8Path(file);
        key += ";";
    }

    for (const fs::path& directory : cmdLine.directories)
    {
        key += "directory=";
        key += FileSystem::toUtf8Path(directory);
        key += ";";
    }

    const uint32_t hash = static_cast<uint32_t>(std::hash<std::string_view>{}(key.view()));
    return std::format("{}_{:08x}", FileSystem::sanitizeFileName(baseName), hash);
}

fs::path NativeArtifactBuilder::workDirectory(const fs::path& workDirRoot, const uint32_t workDirIndex)
{
    return workDirRoot / std::format("{:08x}_{:08x}", Os::currentProcessId(), workDirIndex);
}

Result NativeArtifactBuilder::createWorkDirectory(const fs::path& workDir) const
{
    std::error_code ec;
    fs::create_directories(workDir, ec);
    if (ec)
        return builder_.reportError(DiagnosticId::cmd_err_native_work_dir_create_failed, Diagnostic::ARG_PATH, FileSystem::toUtf8Path(workDir), Diagnostic::ARG_BECAUSE, ec.message());
    return Result::Continue;
}

#if SWC_HAS_UNITTEST

SWC_TEST_BEGIN(NativeArtifactBuilder_QueryPathsUsesSwcNativeTempSubFolder)
CommandLine cmdLine;
Global&     global = const_cast<Global&>(ctx.global());
{
    CommandLineParser parser(global, cmdLine);
    char              arg0[]  = "swc";
    char              arg1[]  = "test";
    char              arg2[]  = "--cfg";
    char              arg3[]  = "debug";
    char              arg4[]  = "--backend-kind";
    char              arg5[]  = "dll";
    char              arg6[]  = "--no-optimize";
    char              arg7[]  = "--native-artifact-base-name";
    char              arg8[]  = "hello";
    char              arg9[]  = "--native-artifact-output-dir";
    char              arg10[] = "native_out";
    char              arg11[] = "--native-work-dir-name";
    char              arg12[] = "tmp_native";
    char              arg13[] = "--no-verify";
    char*             argv[]  = {
        arg0,
        arg1,
        arg2,
        arg3,
        arg4,
        arg5,
        arg6,
        arg7,
        arg8,
        arg9,
        arg10,
        arg11,
        arg12,
        arg13,
    };

    if (parser.parse(static_cast<int>(std::size(argv)), argv) != Result::Continue)
        return Result::Error;
}

CompilerInstance            compiler(global, cmdLine);
NativeBackendBuilder        backendBuilder(compiler, false);
const NativeArtifactBuilder artifactBuilder(backendBuilder);
NativeArtifactPaths         paths;
artifactBuilder.queryPaths(paths, 7, 2);

const Runtime::BuildCfg& buildCfg = compiler.buildCfg();
if (buildCfg.backendKind != Runtime::BuildCfgBackendKind::Library)
    return Result::Error;
if (buildCfg.backend.optimize)
    return Result::Error;
if (!buildCfg.backend.debugInfo)
    return Result::Error;
if (buildCfg.backend.enableExceptions)
    return Result::Error;
if (std::string_view(buildCfg.nativeArtifactBaseName.ptr, buildCfg.nativeArtifactBaseName.length) != "hello")
    return Result::Error;
if (std::string_view(buildCfg.nativeWorkDirName.ptr, buildCfg.nativeWorkDirName.length) != "tmp_native")
    return Result::Error;
if (paths.baseName != "hello")
    return Result::Error;
if (paths.workDirRootName != "tmp_native")
    return Result::Error;
if (paths.artifactExtension != ".dll")
    return Result::Error;
if (paths.artifactOutputDir != cmdLine.nativeArtifactOutputDir)
    return Result::Error;
if (paths.artifactPath != cmdLine.nativeArtifactOutputDir / "hello.dll")
    return Result::Error;

const fs::path expectedWorkDirRoot = Os::getTemporaryPath() / "swc_native" / "tmp_native";
const fs::path expectedWorkDir     = expectedWorkDirRoot / std::format("{:08x}_{:08x}", Os::currentProcessId(), 7u);
if (paths.workDirRoot != expectedWorkDirRoot)
    return Result::Error;
if (paths.workDir != expectedWorkDir)
    return Result::Error;
if (paths.objectPaths.size() != 2)
    return Result::Error;
if (paths.objectPaths[0] != expectedWorkDir / "hello_00.obj")
    return Result::Error;
if (paths.objectPaths[1] != expectedWorkDir / "hello_01.obj")
    return Result::Error;
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
