#include "pch.h"
#include "Backend/Native/NativeBackend_Priv.h"

SWC_BEGIN_NAMESPACE();

namespace NativeBackendDetail
{
    Utf8 makeUtf8(const fs::path& path)
    {
        return {path.generic_string()};
    }

    std::wstring toWide(const std::string_view value)
    {
        if (value.empty())
            return {};

        const int wideCount = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
        if (wideCount <= 0)
            return {};

        std::wstring result;
        result.resize(static_cast<size_t>(wideCount));
        MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), wideCount);
        return result;
    }

    void appendQuotedCommandArg(std::wstring& out, const std::wstring_view arg)
    {
        const bool needsQuotes = arg.empty() || arg.find_first_of(L" \t\"") != std::wstring_view::npos;
        if (!needsQuotes)
        {
            out.append(arg);
            return;
        }

        out.push_back(L'"');
        size_t pendingSlashes = 0;
        for (const wchar_t c : arg)
        {
            if (c == L'\\')
            {
                pendingSlashes++;
                continue;
            }

            if (c == L'"')
            {
                out.append(pendingSlashes * 2 + 1, L'\\');
                out.push_back(L'"');
                pendingSlashes = 0;
                continue;
            }

            if (pendingSlashes)
            {
                out.append(pendingSlashes, L'\\');
                pendingSlashes = 0;
            }

            out.push_back(c);
        }

        if (pendingSlashes)
            out.append(pendingSlashes * 2, L'\\');
        out.push_back(L'"');
    }

    std::optional<Utf8> readEnvUtf8(const char* name)
    {
        char*  value  = nullptr;
        size_t length = 0;
        if (_dupenv_s(&value, &length, name) != 0 || !value || !*value)
        {
            if (value)
                std::free(value);
            return std::nullopt;
        }

        Utf8 result(value);
        std::free(value);
        return result;
    }

    NativeBackendBuilder::NativeBackendBuilder(CompilerInstance& compiler, const bool runArtifact) :
        ctx_(compiler),
        compiler_(compiler),
        runArtifact_(runArtifact)
    {
    }

    Result NativeBackendBuilder::run()
    {
        if (!validateHost())
            return Result::Error;
        if (!collectSymbols())
            return Result::Error;
        if (!scheduleCodeGen())
            return Result::Error;
        if (!validateNativeData())
            return Result::Error;
        if (!prepareDataSections())
            return Result::Error;
        if (!buildStartup())
            return Result::Error;
        if (!partitionObjects())
            return Result::Error;
        if (!writeObjects())
            return Result::Error;
        if (!discoverToolchain())
            return Result::Error;
        if (!linkArtifact())
            return Result::Error;
        if (runArtifact_ && compiler_.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable)
        {
            if (!runGeneratedArtifact())
                return Result::Error;
        }

        return Result::Continue;
    }

    bool NativeBackendBuilder::writeObject(const uint32_t objIndex)
    {
        if (objIndex >= objectDescriptions_.size())
            return reportError("native backend object job index is out of range");

        auto objectWriter = NativeObjectFileWriter::create(*this, ctx_.cmdLine().targetOs);
        if (!objectWriter)
            return reportError("native object file writer is not implemented for this target OS");
        return objectWriter->writeObjectFile(objectDescriptions_[objIndex]);
    }

    Utf8 NativeBackendBuilder::sanitizeName(Utf8 value)
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

    template<typename T>
    void NativeBackendBuilder::sortAndUnique(std::vector<T*>& values) const
    {
        values.erase(std::remove(values.begin(), values.end(), nullptr), values.end());
        std::ranges::sort(values, [&](const T* lhs, const T* rhs) {
            if (lhs == rhs)
                return false;

            const Utf8 lhsKey = makeSortKey(*lhs);
            const Utf8 rhsKey = makeSortKey(*rhs);
            if (lhsKey != rhsKey)
                return lhsKey < rhsKey;
            return lhs < rhs;
        });

        values.erase(std::unique(values.begin(), values.end()), values.end());
    }

    bool NativeBackendBuilder::validateHost() const
    {
        switch (ctx_.cmdLine().targetOs)
        {
            case Runtime::TargetOs::Windows:
                break;

            case Runtime::TargetOs::Linux:
                return reportError("native backend object/link emission is only implemented for Windows targets");

            default:
                return reportError("native backend does not support this target OS");
        }

        if (ctx_.cmdLine().targetArch != Runtime::TargetArch::X86_64)
            return reportError("native backend only supports x86_64 targets");
        if (compiler_.buildCfg().backendKind == Runtime::BuildCfgBackendKind::None)
            return reportError("native backend requires an executable, library, or export backend kind");
        if (compiler_.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable &&
            compiler_.buildCfg().backendSubKind != Runtime::BuildCfgBackendSubKind::Default &&
            compiler_.buildCfg().backendSubKind != Runtime::BuildCfgBackendSubKind::Console)
        {
            return reportError("native backend only supports console executables");
        }

        return true;
    }

    bool NativeBackendBuilder::collectSymbols()
    {
        compiler_.resetNativeCodeSegment();
        rawFunctions_.clear();
        rawTestFunctions_.clear();
        rawInitFunctions_.clear();
        rawPreMainFunctions_.clear();
        rawDropFunctions_.clear();
        rawMainFunctions_.clear();
        regularGlobals_.clear();
        functionInfos_.clear();
        functionBySymbol_.clear();

        const SymbolModule* rootModule = compiler_.symModule();
        if (!rootModule)
            return reportError("semantic analysis did not produce a root symbol module");

        collectSymbolsRec(*rootModule);

        sortAndUnique(rawFunctions_);
        sortAndUnique(rawTestFunctions_);
        sortAndUnique(rawInitFunctions_);
        sortAndUnique(rawPreMainFunctions_);
        sortAndUnique(rawDropFunctions_);
        sortAndUnique(rawMainFunctions_);
        sortAndUnique(regularGlobals_);

        for (SymbolFunction* symbol : rawFunctions_)
        {
            compiler_.addNativeCodeFunction(symbol);

            NativeFunctionInfo info;
            info.symbol      = symbol;
            info.machineCode = &symbol->loweredCode();
            info.sortKey     = makeSymbolSortKey(*symbol);
            info.symbolName  = std::format("__swc_fn_{:06}_{:08x}", functionInfos_.size(), Math::hash(info.sortKey));
            info.exported    = symbol->isPublic() && !isCompilerFunction(*symbol);
            info.compilerFn  = isCompilerFunction(*symbol);
            functionInfos_.push_back(std::move(info));
        }

        for (const auto& info : functionInfos_)
            functionBySymbol_.emplace(info.symbol, &info);

        for (SymbolFunction* symbol : rawTestFunctions_)
            compiler_.addNativeTestFunction(symbol);
        for (SymbolFunction* symbol : rawInitFunctions_)
            compiler_.addNativeInitFunction(symbol);
        for (SymbolFunction* symbol : rawPreMainFunctions_)
            compiler_.addNativePreMainFunction(symbol);
        for (SymbolFunction* symbol : rawDropFunctions_)
            compiler_.addNativeDropFunction(symbol);
        for (SymbolFunction* symbol : rawMainFunctions_)
            compiler_.addNativeMainFunction(symbol);

        return true;
    }

    void NativeBackendBuilder::collectSymbolsRec(const SymbolMap& symbolMap)
    {
        std::vector<const Symbol*> symbols;
        symbolMap.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            if (!symbol)
                continue;

            if (symbol->isFunction())
            {
                auto* function = const_cast<SymbolFunction*>(symbol->safeCast<SymbolFunction>());
                if (function)
                    collectFunction(*function);
                continue;
            }

            if (symbol->isVariable())
            {
                auto* variable = const_cast<SymbolVariable*>(symbol->safeCast<SymbolVariable>());
                if (variable && variable->hasGlobalStorage())
                    regularGlobals_.push_back(variable);
                continue;
            }

            if (symbol->kind() == SymbolKind::Module ||
                symbol->kind() == SymbolKind::Namespace ||
                symbol->kind() == SymbolKind::Struct ||
                symbol->kind() == SymbolKind::Interface ||
                symbol->kind() == SymbolKind::Impl)
            {
                collectSymbolsRec(*const_cast<SymbolMap*>(symbol->asSymMap()));
            }
        }
    }

    void NativeBackendBuilder::collectFunction(SymbolFunction& symbol)
    {
        if (symbol.isForeign() || symbol.isEmpty() || symbol.isAttribute())
            return;
        if (symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
            return;

        const CompilerFunctionKind compilerKind = classifyCompilerFunction(symbol);
        if (compilerKind == CompilerFunctionKind::Excluded)
            return;

        rawFunctions_.push_back(&symbol);
        switch (compilerKind)
        {
            case CompilerFunctionKind::Test:
                rawTestFunctions_.push_back(&symbol);
                break;
            case CompilerFunctionKind::Init:
                rawInitFunctions_.push_back(&symbol);
                break;
            case CompilerFunctionKind::PreMain:
                rawPreMainFunctions_.push_back(&symbol);
                break;
            case CompilerFunctionKind::Drop:
                rawDropFunctions_.push_back(&symbol);
                break;
            case CompilerFunctionKind::Main:
                rawMainFunctions_.push_back(&symbol);
                break;
            case CompilerFunctionKind::None:
            case CompilerFunctionKind::Excluded:
                break;
        }
    }

    NativeBackendBuilder::CompilerFunctionKind NativeBackendBuilder::classifyCompilerFunction(const SymbolFunction& symbol) const
    {
        if (!isCompilerFunction(symbol))
            return CompilerFunctionKind::None;

        const SourceView& srcView = compiler_.srcView(symbol.srcViewRef());
        const Token&      token   = srcView.token(symbol.tokRef());
        switch (token.id)
        {
            case TokenId::CompilerFuncTest:
                return CompilerFunctionKind::Test;
            case TokenId::CompilerFuncInit:
                return CompilerFunctionKind::Init;
            case TokenId::CompilerFuncPreMain:
                return CompilerFunctionKind::PreMain;
            case TokenId::CompilerFuncDrop:
                return CompilerFunctionKind::Drop;
            case TokenId::CompilerFuncMain:
                return CompilerFunctionKind::Main;
            case TokenId::CompilerRun:
            case TokenId::CompilerAst:
            case TokenId::CompilerFuncMessage:
                return CompilerFunctionKind::Excluded;
            default:
                return CompilerFunctionKind::Excluded;
        }
    }

    bool NativeBackendBuilder::isCompilerFunction(const SymbolFunction& symbol)
    {
        return symbol.decl() && symbol.decl()->id() == AstNodeId::CompilerFunc;
    }

    Utf8 NativeBackendBuilder::makeSymbolSortKey(const SymbolFunction& symbol) const
    {
        Utf8 key = symbol.getFullScopedName(ctx_);
        key += "|";
        key += symbol.computeName(ctx_);

        if (const SourceFile* file = compiler_.srcView(symbol.srcViewRef()).file())
        {
            key += "|";
            key += makeUtf8(file->path());
        }

        key += "|";
        key += std::to_string(symbol.tokRef().get());
        return key;
    }

    Utf8 NativeBackendBuilder::makeSortKey(const SymbolFunction& symbol) const
    {
        return makeSymbolSortKey(symbol);
    }

    Utf8 NativeBackendBuilder::makeSortKey(const SymbolVariable& symbol) const
    {
        Utf8 key = symbol.getFullScopedName(ctx_);
        key += "|";
        if (const SourceFile* file = compiler_.srcView(symbol.srcViewRef()).file())
            key += makeUtf8(file->path());
        key += "|";
        key += std::to_string(symbol.tokRef().get());
        return key;
    }

    bool NativeBackendBuilder::scheduleCodeGen()
    {
        if (functionInfos_.empty())
            return true;

        SourceFile* firstFile = nullptr;
        for (SourceFile* file : compiler_.files())
        {
            if (file)
            {
                firstFile = file;
                break;
            }
        }

        if (!firstFile)
            return reportError("native backend did not find a source file for code generation");

        Sema        baseSema(ctx_, firstFile->nodePayloadContext(), false);
        JobManager& jobMgr = ctx_.global().jobMgr();
        for (const auto& info : functionInfos_)
        {
            if (!info.symbol)
                continue;
            if (info.symbol->isCodeGenCompleted() || !info.symbol->loweredCode().bytes.empty())
                continue;
            if (!info.symbol->tryMarkCodeGenJobScheduled())
                continue;

            const AstNodeRef root = info.symbol->declNodeRef();
            if (root.isInvalid())
                return reportError(std::format("function [{}] has no declaration node for code generation", info.symbolName));

            auto* job = heapNew<CodeGenJob>(ctx_, baseSema, *info.symbol, root);
            jobMgr.enqueue(*job, JobPriority::Normal, compiler_.jobClientId());
        }

        Sema::waitDone(ctx_, compiler_.jobClientId());
        if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
            return false;

        for (const auto& info : functionInfos_)
        {
            if (!info.machineCode || info.machineCode->bytes.empty())
                return reportError(std::format("function [{}] did not produce lowered machine code", info.symbolName));
        }

        return true;
    }

    bool NativeBackendBuilder::validateNativeData() const
    {
        if (compiler_.compilerSegment().size() != 0)
            return reportError("compiler data segment is not supported by the native backend");
        if (compiler_.constantSegment().size() != 0)
            return reportError("legacy constant data segment is not supported by the native backend");
        if (!compiler_.globalZeroSegment().relocations().empty())
            return reportError("global zero data relocations are not supported by the native backend");
        if (!compiler_.globalInitSegment().relocations().empty())
            return reportError("global init data relocations are not supported by the native backend");

        for (const SymbolVariable* symbol : regularGlobals_)
        {
            if (!symbol)
                continue;
            if (symbol->globalStorageKind() == DataSegmentKind::Compiler)
                return reportError(std::format("compiler global [{}] is not supported by the native backend", symbol->getFullScopedName(ctx_)));
            if (symbol->globalStorageKind() != DataSegmentKind::GlobalInit)
                continue;
            if (symbol->hasExtraFlag(SymbolVariableFlagsE::ExplicitUndefined))
                return reportError(std::format("undefined global [{}] is not supported by the native backend", symbol->getFullScopedName(ctx_)));
            if (!symbol->cstRef().isValid())
                continue;
            if (!isNativeStaticType(symbol->typeRef()))
                return reportError(std::format("global [{}] has unsupported native static data", symbol->getFullScopedName(ctx_)));
        }

        for (const auto& info : functionInfos_)
        {
            if (!validateRelocations(*info.symbol, *info.machineCode))
                return false;
        }

        return true;
    }

    bool NativeBackendBuilder::isNativeStaticType(const TypeRef typeRef) const
    {
        if (typeRef.isInvalid())
            return false;

        const TypeInfo& typeInfo = ctx_.typeMgr().get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef unwrapped = typeInfo.unwrap(ctx_, typeRef, TypeExpandE::Alias);
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

    bool NativeBackendBuilder::validateRelocations(const SymbolFunction& owner, const MachineCode& code) const
    {
        for (const auto& relocation : code.codeRelocations)
        {
            switch (relocation.kind)
            {
                case MicroRelocation::Kind::CompilerAddress:
                    return reportError(std::format("function [{}] uses compiler-only data", owner.getFullScopedName(ctx_)));

                case MicroRelocation::Kind::LocalFunctionAddress:
                {
                    const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
                    if (!target)
                        return reportError(std::format("function [{}] has an invalid local function relocation", owner.getFullScopedName(ctx_)));
                    if (!functionBySymbol_.contains(const_cast<SymbolFunction*>(target)))
                        return reportError(std::format("function [{}] references unsupported local function [{}]", owner.getFullScopedName(ctx_), target->getFullScopedName(ctx_)));
                    break;
                }

                case MicroRelocation::Kind::ForeignFunctionAddress:
                {
                    const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
                    if (!target || !target->isForeign())
                        return reportError(std::format("function [{}] has an invalid foreign function relocation", owner.getFullScopedName(ctx_)));
                    break;
                }

                case MicroRelocation::Kind::GlobalZeroAddress:
                    if (compiler_.globalZeroSegment().size() == 0)
                        return reportError(std::format("function [{}] references an empty global zero segment", owner.getFullScopedName(ctx_)));
                    break;

                case MicroRelocation::Kind::GlobalInitAddress:
                    if (compiler_.globalInitSegment().size() == 0)
                        return reportError(std::format("function [{}] references an empty global init segment", owner.getFullScopedName(ctx_)));
                    break;

                case MicroRelocation::Kind::ConstantAddress:
                {
                    uint32_t  shardIndex = 0;
                    const Ref ref        = compiler_.cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(relocation.targetAddress));
                    if (ref == INVALID_REF)
                        return reportError(std::format("function [{}] references unsupported constant storage", owner.getFullScopedName(ctx_)));
                    if (!validateConstantRelocation(relocation))
                        return reportError(std::format("function [{}] references unsupported constant payload", owner.getFullScopedName(ctx_)));
                    break;
                }
            }
        }

        return true;
    }

    bool NativeBackendBuilder::validateConstantRelocation(const MicroRelocation& relocation) const
    {
        if (!relocation.constantRef.isValid())
            return false;

        const ConstantValue& constant = compiler_.cstMgr().get(relocation.constantRef);
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
                return compiler_.cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(relocation.targetAddress)) != INVALID_REF;
            }

            case ConstantKind::Null:
                return true;

            default:
                return false;
        }
    }

    bool NativeBackendBuilder::prepareDataSections()
    {
        mergedRData_.name            = ".rdata";
        mergedRData_.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_ALIGN_16BYTES;
        mergedData_.name             = ".data";
        mergedData_.characteristics  = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;
        mergedBss_.name              = ".bss";
        mergedBss_.characteristics   = IMAGE_SCN_CNT_UNINITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;

        mergedRData_.bytes.clear();
        mergedRData_.relocations.clear();
        mergedData_.bytes.clear();
        mergedData_.relocations.clear();
        mergedBss_.bssSize = compiler_.globalZeroSegment().size();
        mergedBss_.bss     = mergedBss_.bssSize != 0;
        rdataShardBaseOffsets_.fill(0);

        for (uint32_t shardIndex = 0; shardIndex < ConstantManager::SHARD_COUNT; ++shardIndex)
        {
            const DataSegment& segment     = compiler_.cstMgr().shardDataSegment(shardIndex);
            const uint32_t     segmentSize = segment.size();
            if (!segmentSize)
                continue;

            const uint32_t baseOffset = Math::alignUpU32(static_cast<uint32_t>(mergedRData_.bytes.size()), 16);
            if (mergedRData_.bytes.size() < baseOffset)
                mergedRData_.bytes.resize(baseOffset, std::byte{0});
            rdataShardBaseOffsets_[shardIndex] = baseOffset;

            const uint32_t insertOffset = static_cast<uint32_t>(mergedRData_.bytes.size());
            mergedRData_.bytes.resize(insertOffset + segmentSize);
            segment.copyTo(ByteSpanRW{mergedRData_.bytes.data() + insertOffset, segmentSize});

            for (const auto& relocation : segment.relocations())
            {
                NativeSectionRelocation record;
                record.offset     = baseOffset + relocation.offset;
                record.symbolName = K_RDataBaseSymbol;
                record.addend     = baseOffset + relocation.targetOffset;
                mergedRData_.relocations.push_back(record);
            }
        }

        const uint32_t dataSize = compiler_.globalInitSegment().size();
        if (dataSize)
        {
            mergedData_.bytes.resize(dataSize);
            compiler_.globalInitSegment().copyTo(ByteSpanRW{mergedData_.bytes.data(), dataSize});
        }

        return true;
    }

    bool NativeBackendBuilder::buildStartup()
    {
        startup_.reset();
        if (compiler_.buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable)
            return true;

        auto         startup = std::make_unique<NativeStartupInfo>();
        MicroBuilder builder(ctx_);
        builder.setBackendBuildCfg(compiler_.buildCfg().backend);

        for (SymbolFunction* symbol : compiler_.nativeInitFunctions())
            ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
        for (SymbolFunction* symbol : compiler_.nativePreMainFunctions())
            ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
        for (SymbolFunction* symbol : compiler_.nativeTestFunctions())
            ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
        for (SymbolFunction* symbol : compiler_.nativeDropFunctions())
            ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});

        auto* exitProcess = Symbol::make<SymbolFunction>(ctx_, nullptr, TokenRef::invalid(), compiler_.idMgr().addIdentifier("ExitProcess"), SymbolFlagsE::Zero);
        exitProcess->attributes().setForeign("kernel32", "ExitProcess");
        exitProcess->setCallConvKind(CallConvKind::Host);
        exitProcess->setReturnTypeRef(compiler_.typeMgr().typeVoid());

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

        if (startup->code.emit(ctx_, builder) != Result::Continue)
            return reportError("failed to lower native test entry point");

        startup_ = std::move(startup);
        return true;
    }

    bool NativeBackendBuilder::partitionObjects()
    {
        objectDescriptions_.clear();

        const size_t functionCount = functionInfos_.size();
        uint32_t     maxJobs       = ctx_.cmdLine().numCores;
        if (!maxJobs)
            maxJobs = std::max<uint32_t>(1, ctx_.global().jobMgr().numWorkers());
        if (!maxJobs)
            maxJobs = 1;

        const uint32_t numJobs = std::max<uint32_t>(1, static_cast<uint32_t>(functionCount ? std::min<size_t>(functionCount, maxJobs) : 1));
        objectDescriptions_.resize(numJobs);

        const Utf8 baseName = artifactBaseName();
        if (!createWorkDirectory(baseName))
            return false;

        for (uint32_t i = 0; i < numJobs; ++i)
        {
            objectDescriptions_[i].index       = i;
            objectDescriptions_[i].includeData = i == 0;
            objectDescriptions_[i].objPath     = workDir_ / std::format("{}_{:02}.obj", baseName, i);
        }

        if (startup_)
            objectDescriptions_[0].startup = startup_.get();

        for (size_t i = 0; i < functionInfos_.size(); ++i)
        {
            NativeFunctionInfo& info     = functionInfos_[i];
            const uint32_t      objIndex = static_cast<uint32_t>(i % numJobs);
            info.jobIndex                = objIndex;
            objectDescriptions_[objIndex].functions.push_back(&info);
        }

        artifactPath_ = workDir_ / std::format("{}{}", baseName, artifactExtension());
        return true;
    }

    Utf8 NativeBackendBuilder::artifactBaseName() const
    {
        if (!ctx_.cmdLine().modulePath.empty())
            return sanitizeName(Utf8(ctx_.cmdLine().modulePath.filename().string()));
        if (ctx_.cmdLine().files.size() == 1)
            return sanitizeName(Utf8(ctx_.cmdLine().files.begin()->stem().string()));
        if (ctx_.cmdLine().directories.size() == 1)
            return sanitizeName(Utf8(ctx_.cmdLine().directories.begin()->filename().string()));
        return "native_test";
    }

    Utf8 NativeBackendBuilder::artifactExtension() const
    {
        switch (compiler_.buildCfg().backendKind)
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

        SWC_UNREACHABLE();
    }

    bool NativeBackendBuilder::createWorkDirectory(const Utf8& baseName)
    {
        std::error_code ec;
        workDir_ = Os::getTemporaryPath() / std::format("swc_native_{}_{}_{}", baseName, Os::currentProcessId(), compiler_.atomicId().fetch_add(1, std::memory_order_relaxed));
        fs::create_directories(workDir_, ec);
        if (ec)
            return reportError(std::format("cannot create native backend work directory [{}]: {}", makeUtf8(workDir_), ec.message()));
        return true;
    }

    bool NativeBackendBuilder::writeObjects()
    {
        objWriteFailed_.store(false, std::memory_order_release);
        JobManager& jobMgr = ctx_.global().jobMgr();
        for (uint32_t i = 0; i < objectDescriptions_.size(); ++i)
        {
            auto* job = heapNew<NativeObjJob>(ctx_, *this, i);
            jobMgr.enqueue(*job, JobPriority::Normal, compiler_.jobClientId());
        }

        jobMgr.waitAll(compiler_.jobClientId());
        return !objWriteFailed_.load(std::memory_order_acquire);
    }

    bool NativeBackendBuilder::reportError(const std::string_view because) const
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_native_backend);
        diag.addArgument(Diagnostic::ARG_BECAUSE, because);
        diag.report(const_cast<TaskContext&>(ctx_));
        return false;
    }

    NativeObjJob::NativeObjJob(const TaskContext& ctx, NativeBackendBuilder& builder, const uint32_t objIndex) :
        Job(ctx, JobKind::NativeObj),
        builder_(&builder),
        objIndex_(objIndex)
    {
        func = [this] {
            return exec();
        };
    }

    JobResult NativeObjJob::exec()
    {
        ctx().state().reset();
        if (!builder_)
            return JobResult::Done;
        if (!builder_->writeObject(objIndex_))
            builder_->objWriteFailed_.store(true, std::memory_order_release);
        return JobResult::Done;
    }
}

namespace NativeBackend
{
    Result run(CompilerInstance& compiler, const bool runArtifact)
    {
        NativeBackendDetail::NativeBackendBuilder builder(compiler, runArtifact);
        return builder.run();
    }
}

SWC_END_NAMESPACE();
