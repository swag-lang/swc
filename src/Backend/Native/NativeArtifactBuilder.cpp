#include "pch.h"

#include "Backend/ABI/ABICall.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Main/Global.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

NativeArtifactBuilder::NativeArtifactBuilder(NativeBackendBuilder& builder) :
    builder_(builder)
{
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
    const auto& state    = builder_.state();

    if (compiler.compilerSegment().size() != 0)
        return builder_.reportError(DiagnosticId::cmd_err_native_compiler_segment_unsupported);
    if (compiler.constantSegment().size() != 0)
        return builder_.reportError(DiagnosticId::cmd_err_native_constant_segment_unsupported);
    if (!compiler.globalZeroSegment().relocations().empty())
        return builder_.reportError(DiagnosticId::cmd_err_native_global_zero_relocations_unsupported);
    if (!compiler.globalInitSegment().relocations().empty())
        return builder_.reportError(DiagnosticId::cmd_err_native_global_init_relocations_unsupported);

    for (const SymbolVariable* symbol : state.regularGlobals)
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

    for (const auto& info : state.functionInfos)
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
    const auto& state = builder_.state();

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
                if (!state.functionBySymbol.contains(const_cast<SymbolFunction*>(target)))
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
    auto& state = builder_.state();

    state.mergedRData.name            = ".rdata";
    state.mergedRData.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_ALIGN_16BYTES;
    state.mergedData.name             = ".data";
    state.mergedData.characteristics  = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;
    state.mergedBss.name              = ".bss";
    state.mergedBss.characteristics   = IMAGE_SCN_CNT_UNINITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;

    state.mergedRData.bytes.clear();
    state.mergedRData.relocations.clear();
    state.mergedData.bytes.clear();
    state.mergedData.relocations.clear();
    state.mergedBss.bssSize = builder_.compiler().globalZeroSegment().size();
    state.mergedBss.bss     = state.mergedBss.bssSize != 0;
    state.rdataShardBaseOffsets.fill(0);

    for (uint32_t shardIndex = 0; shardIndex < ConstantManager::SHARD_COUNT; ++shardIndex)
    {
        const DataSegment& segment     = builder_.compiler().cstMgr().shardDataSegment(shardIndex);
        const uint32_t     segmentSize = segment.size();
        if (!segmentSize)
            continue;

        const uint32_t baseOffset = Math::alignUpU32(static_cast<uint32_t>(state.mergedRData.bytes.size()), 16);
        if (state.mergedRData.bytes.size() < baseOffset)
            state.mergedRData.bytes.resize(baseOffset, std::byte{0});
        state.rdataShardBaseOffsets[shardIndex] = baseOffset;

        const uint32_t insertOffset = static_cast<uint32_t>(state.mergedRData.bytes.size());
        state.mergedRData.bytes.resize(insertOffset + segmentSize);
        segment.copyTo(ByteSpanRW{state.mergedRData.bytes.data() + insertOffset, segmentSize});

        for (const auto& relocation : segment.relocations())
        {
            NativeSectionRelocation record;
            record.offset     = baseOffset + relocation.offset;
            record.symbolName = K_R_DATA_BASE_SYMBOL;
            record.addend     = baseOffset + relocation.targetOffset;
            state.mergedRData.relocations.push_back(record);
        }
    }

    const uint32_t dataSize = builder_.compiler().globalInitSegment().size();
    if (dataSize)
    {
        state.mergedData.bytes.resize(dataSize);
        builder_.compiler().globalInitSegment().copyTo(ByteSpanRW{state.mergedData.bytes.data(), dataSize});
    }

    return Result::Continue;
}

Result NativeArtifactBuilder::buildStartup() const
{
    auto& state = builder_.state();
    state.startup.reset();

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

    state.startup = std::move(startup);
    return Result::Continue;
}

Result NativeArtifactBuilder::partitionObjects() const
{
    auto& state = builder_.state();
    state.objectDescriptions.clear();

    const size_t functionCount = state.functionInfos.size();
    uint32_t     maxJobs       = builder_.ctx().cmdLine().numCores;
    if (!maxJobs)
        maxJobs = std::max<uint32_t>(1, builder_.ctx().global().jobMgr().numWorkers());
    if (!maxJobs)
        maxJobs = 1;

    const uint32_t numJobs = std::max<uint32_t>(1, static_cast<uint32_t>(functionCount ? std::min<size_t>(functionCount, maxJobs) : 1));
    state.objectDescriptions.resize(numJobs);

    const Utf8 baseName = artifactBaseName();
    SWC_RESULT_VERIFY(createWorkDirectory(baseName));

    for (uint32_t i = 0; i < numJobs; ++i)
    {
        state.objectDescriptions[i].index       = i;
        state.objectDescriptions[i].includeData = i == 0;
        state.objectDescriptions[i].objPath     = state.workDir / std::format("{}_{:02}.obj", baseName, i);
    }

    if (state.startup)
        state.objectDescriptions[0].startup = state.startup.get();

    for (size_t i = 0; i < state.functionInfos.size(); ++i)
    {
        NativeFunctionInfo& info     = state.functionInfos[i];
        const uint32_t      objIndex = static_cast<uint32_t>(i % numJobs);
        info.jobIndex                = objIndex;
        state.objectDescriptions[objIndex].functions.push_back(&info);
    }

    state.artifactPath = state.workDir / std::format("{}{}", baseName, artifactExtension());
    return Result::Continue;
}

Utf8 NativeArtifactBuilder::artifactBaseName() const
{
    const auto& cmdLine = builder_.ctx().cmdLine();

    if (!cmdLine.modulePath.empty())
        return sanitizeName(Utf8(cmdLine.modulePath.filename().string()));
    if (cmdLine.files.size() == 1)
        return sanitizeName(Utf8(cmdLine.files.begin()->stem().string()));
    if (cmdLine.directories.size() == 1)
        return sanitizeName(Utf8(cmdLine.directories.begin()->filename().string()));
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

Result NativeArtifactBuilder::createWorkDirectory(const Utf8& baseName) const
{
    std::error_code ec;
    builder_.state().workDir = Os::getTemporaryPath() / std::format("swc_native_{}_{}_{}", baseName, Os::currentProcessId(), builder_.compiler().atomicId().fetch_add(1, std::memory_order_relaxed));
    fs::create_directories(builder_.state().workDir, ec);
    if (ec)
        return builder_.reportError(DiagnosticId::cmd_err_native_work_dir_create_failed, Diagnostic::ARG_PATH, makeUtf8(builder_.state().workDir), Diagnostic::ARG_BECAUSE, ec.message());
    return Result::Continue;
}

Utf8 NativeArtifactBuilder::sanitizeName(Utf8 value)
{
    if (value.empty())
        return "native";

    for (char& c : value)
    {
        if ((c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') ||
            c == '_' ||
            c == '-')
        {
            continue;
        }

        c = '_';
    }

    return value;
}

SWC_END_NAMESPACE();
