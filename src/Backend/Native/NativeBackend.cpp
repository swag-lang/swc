#include "pch.h"
#include "Backend/Native/NativeBackend.h"
#include "Backend/ABI/ABICall.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Math/Hash.h"
#include "Support/Math/Helpers.h"
#include "Support/Memory/Heap.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Thread/JobManager.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr auto K_RDataBaseSymbol = "__swc_rdata_base";
    constexpr auto K_DataBaseSymbol  = "__swc_data_base";
    constexpr auto K_BssBaseSymbol   = "__swc_bss_base";

    Utf8 makeUtf8(const fs::path& path)
    {
        return Utf8(path.generic_string());
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

    struct NativeToolchain
    {
        fs::path linkExe;
        fs::path libExe;
        fs::path vcLibPath;
        fs::path sdkUmLibPath;
        fs::path sdkUcrtLibPath;
    };

    struct NativeFunctionInfo
    {
        SymbolFunction*    symbol      = nullptr;
        const MachineCode* machineCode = nullptr;
        Utf8               sortKey;
        Utf8               symbolName;
        uint32_t           jobIndex   = 0;
        uint32_t           textOffset = 0;
        bool               exported   = false;
        bool               compilerFn = false;
    };

    struct NativeStartupInfo
    {
        MachineCode code;
        Utf8        symbolName = "mainCRTStartup";
        uint32_t    textOffset = 0;
    };

    struct NativeSectionRelocation
    {
        uint32_t offset = 0;
        Utf8     symbolName;
        uint64_t addend = 0;
        uint16_t type   = IMAGE_REL_AMD64_ADDR64;
    };

    struct NativeSectionData
    {
        Utf8                                 name;
        std::vector<std::byte>               bytes;
        std::vector<NativeSectionRelocation> relocations;
        uint32_t                             characteristics = 0;
        bool                                 bss             = false;
        uint32_t                             bssSize         = 0;
    };

    struct NativeObjDescription
    {
        uint32_t                          index       = 0;
        fs::path                          objPath;
        std::vector<NativeFunctionInfo*>  functions;
        NativeStartupInfo*                startup     = nullptr;
        bool                              includeData = false;
    };

    struct CoffSymbolRecord
    {
        Utf8     name;
        int16_t  sectionNumber = 0;
        uint32_t value         = 0;
        uint16_t type          = 0;
        uint8_t  storageClass  = 0;
        uint8_t  numAuxSymbols = 0;
    };

    struct CoffSectionBuild
    {
        NativeSectionData                  data;
        std::vector<NativeSectionRelocation> relocations;
        uint16_t                           sectionNumber        = 0;
        uint32_t                           pointerToRawData     = 0;
        uint32_t                           pointerToRelocations = 0;
        uint16_t                           numberOfRelocations  = 0;
        uint32_t                           sizeOfRawData        = 0;
    };

    class NativeBackendBuilder;

    class NativeObjJob final : public Job
    {
    public:
        static constexpr auto K = JobKind::NativeObj;

        NativeObjJob(const TaskContext& ctx, NativeBackendBuilder& builder, uint32_t objIndex);

    private:
        JobResult exec();

        NativeBackendBuilder* builder_  = nullptr;
        uint32_t              objIndex_ = 0;
    };

    class NativeBackendBuilder
    {
        friend class NativeObjJob;

    public:
        NativeBackendBuilder(CompilerInstance& compiler, bool runArtifact);
        Result run();
        bool   writeObject(uint32_t objIndex);

    private:
        enum class CompilerFunctionKind : uint8_t
        {
            None,
            Test,
            Init,
            PreMain,
            Drop,
            Main,
            Excluded,
        };

        template<typename T>
        void sortAndUnique(std::vector<T*>& values) const;

        bool               validateHost();
        bool               collectSymbols();
        void               collectSymbolsRec(SymbolMap& symbolMap);
        void               collectFunction(SymbolFunction& symbol);
        CompilerFunctionKind classifyCompilerFunction(const SymbolFunction& symbol) const;
        bool               isCompilerFunction(const SymbolFunction& symbol) const;
        Utf8               makeSymbolSortKey(const SymbolFunction& symbol) const;
        Utf8               makeSortKey(const SymbolFunction& symbol) const;
        Utf8               makeSortKey(const SymbolVariable& symbol) const;
        bool               scheduleCodeGen();
        bool               validateNativeData();
        bool               isNativeStaticType(TypeRef typeRef) const;
        bool               validateRelocations(const SymbolFunction& owner, const MachineCode& code) const;
        bool               validateConstantRelocation(const MicroRelocation& relocation) const;
        bool               prepareDataSections();
        bool               buildStartup();
        bool               partitionObjects();
        Utf8               artifactBaseName() const;
        Utf8               artifactExtension() const;
        bool               createWorkDirectory(const Utf8& baseName);
        bool               writeObjects();
        bool               discoverToolchain();
        bool               discoverMsvcToolchain();
        bool               discoverWindowsSdk();
        bool               linkArtifact();
        std::vector<Utf8>  buildLinkArguments(bool dll) const;
        std::vector<Utf8>  buildLibArguments() const;
        void               appendLinkSearchPaths(std::vector<Utf8>& args) const;
        void               collectLinkLibraries(std::set<Utf8>& out) const;
        Utf8               normalizeLibraryName(std::string_view value) const;
        void               appendUserLinkerArgs(std::vector<Utf8>& args) const;
        bool               runGeneratedArtifact();
        bool               runProcess(const fs::path& exePath, const std::vector<Utf8>& args, const fs::path& workingDirectory, uint32_t& outExitCode) const;
        bool               writeObjectFile(const NativeObjDescription& description);
        bool               buildTextSection(const NativeObjDescription& description, CoffSectionBuild& textSection);
        bool               appendCodeRelocations(const NativeStartupInfo& startup, const MachineCode& code, CoffSectionBuild& textSection);
        bool               appendCodeRelocations(const NativeFunctionInfo& owner, const MachineCode& code, CoffSectionBuild& textSection);
        bool               appendSingleCodeRelocation(uint32_t functionOffset, const MicroRelocation& relocation, CoffSectionBuild& textSection);
        bool               buildDataRelocations(CoffSectionBuild& section) const;
        static void        writeU64(std::vector<std::byte>& bytes, uint32_t offset, uint64_t value);
        void               addDefinedSymbols(const NativeObjDescription& description, const std::vector<CoffSectionBuild>& sections, std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices) const;
        void               addUndefinedSymbols(const std::vector<CoffSectionBuild>& sections, std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices) const;
        bool               flushCoffFile(const fs::path& objPath, std::vector<CoffSectionBuild>& sections, const std::vector<CoffSymbolRecord>& symbols, const std::unordered_map<Utf8, uint32_t>& symbolIndices) const;
        bool               reportError(std::string_view because) const;
        static Utf8        sanitizeName(Utf8 value);

        TaskContext                                                  ctx_;
        CompilerInstance&                                            compiler_;
        bool                                                         runArtifact_ = false;
        std::vector<SymbolFunction*>                                 rawFunctions_;
        std::vector<SymbolFunction*>                                 rawTestFunctions_;
        std::vector<SymbolFunction*>                                 rawInitFunctions_;
        std::vector<SymbolFunction*>                                 rawPreMainFunctions_;
        std::vector<SymbolFunction*>                                 rawDropFunctions_;
        std::vector<SymbolFunction*>                                 rawMainFunctions_;
        std::vector<SymbolVariable*>                                 regularGlobals_;
        std::vector<NativeFunctionInfo>                              functionInfos_;
        std::unordered_map<SymbolFunction*, const NativeFunctionInfo*> functionBySymbol_;
        std::unique_ptr<NativeStartupInfo>                           startup_;
        NativeSectionData                                            mergedRData_;
        NativeSectionData                                            mergedData_;
        NativeSectionData                                            mergedBss_;
        std::array<uint32_t, ConstantManager::SHARD_COUNT>           rdataShardBaseOffsets_{};
        std::vector<NativeObjDescription>                            objectDescriptions_;
        NativeToolchain                                              toolchain_;
        fs::path                                                     workDir_;
        fs::path                                                     artifactPath_;
        std::atomic<bool>                                            objWriteFailed_ = false;
    };

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
        return writeObjectFile(objectDescriptions_[objIndex]);
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

    bool NativeBackendBuilder::validateHost()
    {
        if (ctx_.cmdLine().targetOs != Runtime::TargetOs::Windows)
            return reportError("native backend only supports Windows targets");
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

        SymbolModule* const rootModule = compiler_.symModule();
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

    void NativeBackendBuilder::collectSymbolsRec(SymbolMap& symbolMap)
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

    bool NativeBackendBuilder::isCompilerFunction(const SymbolFunction& symbol) const
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

        Sema       baseSema(ctx_, firstFile->nodePayloadContext(), false);
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

    bool NativeBackendBuilder::validateNativeData()
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
                    uint32_t shardIndex = 0;
                    const Ref ref = compiler_.cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(relocation.targetAddress));
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

        auto startup = std::make_unique<NativeStartupInfo>();
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
            NativeFunctionInfo& info = functionInfos_[i];
            const uint32_t      objIndex = static_cast<uint32_t>(i % numJobs);
            info.jobIndex = objIndex;
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

    bool NativeBackendBuilder::discoverToolchain()
    {
        toolchain_ = {};
        if (!discoverMsvcToolchain())
            return false;
        if (!discoverWindowsSdk())
            return false;
        return true;
    }

    bool NativeBackendBuilder::discoverMsvcToolchain()
    {
        std::vector<fs::path> candidates;

        if (const auto vctools = readEnvUtf8("VCToolsInstallDir"))
            candidates.emplace_back(std::string(*vctools));

        const auto appendRoots = [&](const fs::path& basePath) {
            std::error_code ec;
            if (!fs::exists(basePath, ec))
                return;

            std::vector<fs::path> versionRoots;
            for (fs::directory_iterator it(basePath, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
            {
                if (ec)
                {
                    ec.clear();
                    continue;
                }

                if (!it->is_directory(ec))
                {
                    ec.clear();
                    continue;
                }

                for (fs::directory_iterator skuIt(it->path(), fs::directory_options::skip_permission_denied, ec), skuEnd; skuIt != skuEnd; skuIt.increment(ec))
                {
                    if (ec)
                    {
                        ec.clear();
                        continue;
                    }

                    if (!skuIt->is_directory(ec))
                    {
                        ec.clear();
                        continue;
                    }

                    const fs::path toolsDir = skuIt->path() / "VC" / "Tools" / "MSVC";
                    if (!fs::exists(toolsDir, ec))
                        continue;

                    for (fs::directory_iterator toolIt(toolsDir, fs::directory_options::skip_permission_denied, ec), toolEnd; toolIt != toolEnd; toolIt.increment(ec))
                    {
                        if (ec)
                        {
                            ec.clear();
                            continue;
                        }

                        if (toolIt->is_directory(ec))
                            versionRoots.push_back(toolIt->path());
                    }
                }
            }

            std::ranges::sort(versionRoots, std::greater<>{}, [](const fs::path& path) {
                return path.filename().generic_string();
            });
            for (const auto& one : versionRoots)
                candidates.push_back(one);
        };

        appendRoots("C:\\Program Files\\Microsoft Visual Studio");
        appendRoots("C:\\Program Files (x86)\\Microsoft Visual Studio");

        for (const auto& root : candidates)
        {
            std::error_code ec;
            const fs::path  linkExe = root / "bin" / "Hostx64" / "x64" / "link.exe";
            const fs::path  libExe  = root / "bin" / "Hostx64" / "x64" / "lib.exe";
            const fs::path  vcLib   = root / "lib" / "x64";
            if (!fs::exists(linkExe, ec) || !fs::exists(libExe, ec))
                continue;

            toolchain_.linkExe   = linkExe;
            toolchain_.libExe    = libExe;
            toolchain_.vcLibPath = vcLib;
            return true;
        }

        return reportError("cannot find link.exe/lib.exe for the Windows native backend");
    }

    bool NativeBackendBuilder::discoverWindowsSdk()
    {
        std::vector<fs::path> candidates;

        if (const auto sdkDir = readEnvUtf8("WindowsSdkDir"))
        {
            const fs::path libRoot = fs::path(std::string(*sdkDir)) / "Lib";
            if (const auto sdkVersion = readEnvUtf8("WindowsSDKVersion"))
                candidates.emplace_back(libRoot / std::string(*sdkVersion));
        }

        std::error_code ec;
        const fs::path sdkRoot = "C:\\Program Files (x86)\\Windows Kits\\10\\Lib";
        if (fs::exists(sdkRoot, ec))
        {
            std::vector<fs::path> versions;
            for (fs::directory_iterator it(sdkRoot, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
            {
                if (ec)
                {
                    ec.clear();
                    continue;
                }

                if (it->is_directory(ec))
                    versions.push_back(it->path());
            }

            std::ranges::sort(versions, std::greater<>{}, [](const fs::path& path) {
                return path.filename().generic_string();
            });
            for (const auto& version : versions)
                candidates.push_back(version);
        }

        for (const auto& root : candidates)
        {
            const fs::path umLib   = root / "um" / "x64";
            const fs::path ucrtLib = root / "ucrt" / "x64";
            if (!fs::exists(umLib, ec) || !fs::exists(ucrtLib, ec))
                continue;

            toolchain_.sdkUmLibPath   = umLib;
            toolchain_.sdkUcrtLibPath = ucrtLib;
            return true;
        }

        return reportError("cannot find Windows SDK libraries for the native backend");
    }

    bool NativeBackendBuilder::linkArtifact()
    {
        std::vector<Utf8> args;
        const fs::path*   exePath = nullptr;
        switch (compiler_.buildCfg().backendKind)
        {
            case Runtime::BuildCfgBackendKind::Executable:
                args    = buildLinkArguments(false);
                exePath = &toolchain_.linkExe;
                break;
            case Runtime::BuildCfgBackendKind::Library:
                args    = buildLinkArguments(true);
                exePath = &toolchain_.linkExe;
                break;
            case Runtime::BuildCfgBackendKind::Export:
                args    = buildLibArguments();
                exePath = &toolchain_.libExe;
                break;
            case Runtime::BuildCfgBackendKind::None:
                return reportError("invalid native backend kind");
        }

        uint32_t exitCode = 0;
        if (!runProcess(*exePath, args, workDir_, exitCode))
            return false;
        if (exitCode != 0)
            return reportError(std::format("{} exited with code {}", makeUtf8(exePath->filename()), exitCode));
        if (!fs::exists(artifactPath_))
            return reportError(std::format("native backend did not produce [{}]", makeUtf8(artifactPath_)));
        return true;
    }

    std::vector<Utf8> NativeBackendBuilder::buildLinkArguments(const bool dll) const
    {
        std::vector<Utf8> args;
        args.push_back("/NOLOGO");
        args.push_back("/NODEFAULTLIB");
        args.push_back("/INCREMENTAL:NO");
        args.push_back("/MACHINE:X64");
        if (dll)
        {
            args.push_back("/DLL");
            args.push_back("/NOENTRY");
        }
        else
        {
            args.push_back("/SUBSYSTEM:CONSOLE");
            args.push_back("/ENTRY:mainCRTStartup");
        }

        args.push_back(std::format("/OUT:{}", makeUtf8(artifactPath_)));
        appendLinkSearchPaths(args);

        for (const auto& object : objectDescriptions_)
            args.push_back(makeUtf8(object.objPath));

        std::set<Utf8> libraries;
        collectLinkLibraries(libraries);
        for (const Utf8& library : libraries)
            args.push_back(library);

        if (dll)
        {
            for (const auto& info : functionInfos_)
            {
                if (info.exported)
                    args.push_back(std::format("/EXPORT:{}", info.symbolName));
            }
        }

        appendUserLinkerArgs(args);
        return args;
    }

    std::vector<Utf8> NativeBackendBuilder::buildLibArguments() const
    {
        std::vector<Utf8> args;
        args.push_back("/NOLOGO");
        args.push_back("/MACHINE:X64");
        args.push_back(std::format("/OUT:{}", makeUtf8(artifactPath_)));
        for (const auto& object : objectDescriptions_)
            args.push_back(makeUtf8(object.objPath));
        return args;
    }

    void NativeBackendBuilder::appendLinkSearchPaths(std::vector<Utf8>& args) const
    {
        if (!toolchain_.vcLibPath.empty())
            args.push_back(std::format("/LIBPATH:{}", makeUtf8(toolchain_.vcLibPath)));
        if (!toolchain_.sdkUmLibPath.empty())
            args.push_back(std::format("/LIBPATH:{}", makeUtf8(toolchain_.sdkUmLibPath)));
        if (!toolchain_.sdkUcrtLibPath.empty())
            args.push_back(std::format("/LIBPATH:{}", makeUtf8(toolchain_.sdkUcrtLibPath)));
    }

    void NativeBackendBuilder::collectLinkLibraries(std::set<Utf8>& out) const
    {
        for (const Utf8& library : compiler_.foreignLibs())
            out.insert(normalizeLibraryName(library));

        const auto collectFromCode = [&](const MachineCode& code) {
            for (const auto& relocation : code.codeRelocations)
            {
                if (relocation.kind != MicroRelocation::Kind::ForeignFunctionAddress || !relocation.targetSymbol)
                    continue;
                const auto* function = relocation.targetSymbol->safeCast<SymbolFunction>();
                if (!function)
                    continue;
                if (!function->foreignModuleName().empty())
                    out.insert(normalizeLibraryName(function->foreignModuleName()));
            }
        };

        for (const auto& info : functionInfos_)
            collectFromCode(*info.machineCode);
        if (startup_)
            collectFromCode(startup_->code);
    }

    Utf8 NativeBackendBuilder::normalizeLibraryName(const std::string_view value) const
    {
        Utf8 out(value);
        if (fs::path(std::string(out)).extension().empty())
            out += ".lib";
        out.make_lower();
        return out;
    }

    void NativeBackendBuilder::appendUserLinkerArgs(std::vector<Utf8>& args) const
    {
        const Runtime::String& linkerArgs = compiler_.buildCfg().linkerArgs;
        if (!linkerArgs.ptr || linkerArgs.length == 0)
            return;

        const std::string_view raw(linkerArgs.ptr, static_cast<size_t>(linkerArgs.length));
        size_t                 index = 0;
        while (index < raw.size())
        {
            while (index < raw.size() && std::isspace(static_cast<unsigned char>(raw[index])))
                ++index;
            if (index >= raw.size())
                break;

            size_t end = index;
            while (end < raw.size() && !std::isspace(static_cast<unsigned char>(raw[end])))
                ++end;
            args.emplace_back(raw.substr(index, end - index));
            index = end;
        }
    }

    bool NativeBackendBuilder::runGeneratedArtifact()
    {
        uint32_t exitCode = 0;
        if (!runProcess(artifactPath_, {}, workDir_, exitCode))
            return false;
        if (exitCode != 0)
            return reportError(std::format("generated executable exited with code {}", exitCode));
        return true;
    }

    bool NativeBackendBuilder::runProcess(const fs::path& exePath,
                                          const std::vector<Utf8>& args,
                                          const fs::path& workingDirectory,
                                          uint32_t& outExitCode) const
    {
        std::wstring commandLine;
        appendQuotedCommandArg(commandLine, exePath.wstring());
        for (const Utf8& arg : args)
        {
            commandLine.push_back(L' ');
            appendQuotedCommandArg(commandLine, toWide(arg));
        }

        STARTUPINFOW        startupInfo{};
        PROCESS_INFORMATION processInfo{};
        startupInfo.cb = sizeof(startupInfo);

        std::wstring mutableCommandLine = commandLine;
        const std::wstring workingDirW  = workingDirectory.empty() ? std::wstring() : workingDirectory.wstring();
        if (!CreateProcessW(exePath.wstring().c_str(),
                            mutableCommandLine.data(),
                            nullptr,
                            nullptr,
                            FALSE,
                            0,
                            nullptr,
                            workingDirW.empty() ? nullptr : workingDirW.c_str(),
                            &startupInfo,
                            &processInfo))
        {
            return reportError(std::format("cannot start [{}]: {}", makeUtf8(exePath), Os::systemError()));
        }

        const DWORD waitResult = WaitForSingleObject(processInfo.hProcess, INFINITE);
        if (waitResult != WAIT_OBJECT_0)
        {
            CloseHandle(processInfo.hThread);
            CloseHandle(processInfo.hProcess);
            return reportError(std::format("waiting for [{}] failed", makeUtf8(exePath)));
        }

        DWORD exitCode = 0;
        if (!GetExitCodeProcess(processInfo.hProcess, &exitCode))
        {
            CloseHandle(processInfo.hThread);
            CloseHandle(processInfo.hProcess);
            return reportError(std::format("cannot get exit code for [{}]: {}", makeUtf8(exePath), Os::systemError()));
        }

        CloseHandle(processInfo.hThread);
        CloseHandle(processInfo.hProcess);
        outExitCode = exitCode;
        return true;
    }

    bool NativeBackendBuilder::writeObjectFile(const NativeObjDescription& description)
    {
        CoffSectionBuild textSection;
        textSection.data.name            = ".text";
        textSection.data.characteristics = IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_READ | IMAGE_SCN_ALIGN_16BYTES;
        if (!buildTextSection(description, textSection))
            return false;

        std::vector<CoffSectionBuild> sections;
        sections.push_back(std::move(textSection));

        if (description.includeData && !mergedRData_.bytes.empty())
        {
            CoffSectionBuild section;
            section.data = mergedRData_;
            if (!buildDataRelocations(section))
                return false;
            sections.push_back(std::move(section));
        }

        if (description.includeData && !mergedData_.bytes.empty())
        {
            CoffSectionBuild section;
            section.data = mergedData_;
            sections.push_back(std::move(section));
        }

        if (description.includeData && mergedBss_.bss)
        {
            CoffSectionBuild section;
            section.data = mergedBss_;
            sections.push_back(std::move(section));
        }

        for (uint16_t i = 0; i < sections.size(); ++i)
            sections[i].sectionNumber = static_cast<uint16_t>(i + 1);

        std::vector<CoffSymbolRecord>   symbols;
        std::unordered_map<Utf8, uint32_t> symbolIndices;
        addDefinedSymbols(description, sections, symbols, symbolIndices);
        addUndefinedSymbols(sections, symbols, symbolIndices);

        return flushCoffFile(description.objPath, sections, symbols, symbolIndices);
    }

    bool NativeBackendBuilder::buildTextSection(const NativeObjDescription& description, CoffSectionBuild& textSection)
    {
        const auto appendCode = [&](uint32_t& outOffset, const std::vector<std::byte>& bytes) {
            const uint32_t alignedOffset = Math::alignUpU32(static_cast<uint32_t>(textSection.data.bytes.size()), 16);
            if (textSection.data.bytes.size() < alignedOffset)
                textSection.data.bytes.resize(alignedOffset, std::byte{0});
            outOffset = alignedOffset;
            textSection.data.bytes.insert(textSection.data.bytes.end(), bytes.begin(), bytes.end());
        };

        if (description.startup)
            appendCode(description.startup->textOffset, description.startup->code.bytes);
        for (NativeFunctionInfo* info : description.functions)
        {
            if (info)
                appendCode(info->textOffset, info->machineCode->bytes);
        }

        if (description.startup && !appendCodeRelocations(*description.startup, description.startup->code, textSection))
            return false;
        for (NativeFunctionInfo* info : description.functions)
        {
            if (info && !appendCodeRelocations(*info, *info->machineCode, textSection))
                return false;
        }

        return true;
    }

    bool NativeBackendBuilder::appendCodeRelocations(const NativeStartupInfo& startup, const MachineCode& code, CoffSectionBuild& textSection)
    {
        for (const auto& relocation : code.codeRelocations)
        {
            if (!appendSingleCodeRelocation(startup.textOffset, relocation, textSection))
                return false;
        }

        return true;
    }

    bool NativeBackendBuilder::appendCodeRelocations(const NativeFunctionInfo& owner, const MachineCode& code, CoffSectionBuild& textSection)
    {
        for (const auto& relocation : code.codeRelocations)
        {
            if (!appendSingleCodeRelocation(owner.textOffset, relocation, textSection))
                return false;
        }

        return true;
    }

    bool NativeBackendBuilder::appendSingleCodeRelocation(const uint32_t functionOffset,
                                                          const MicroRelocation& relocation,
                                                          CoffSectionBuild& textSection)
    {
        const uint32_t patchOffset = functionOffset + relocation.codeOffset;
        if (patchOffset + sizeof(uint64_t) > textSection.data.bytes.size())
            return reportError("native backend text relocation offset is out of range");

        NativeSectionRelocation record;
        record.offset = patchOffset;

        switch (relocation.kind)
        {
            case MicroRelocation::Kind::LocalFunctionAddress:
            {
                const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
                if (!target)
                    return reportError("native backend encountered an invalid local relocation target");
                const auto it = functionBySymbol_.find(const_cast<SymbolFunction*>(target));
                if (it == functionBySymbol_.end())
                    return reportError(std::format("native backend cannot resolve local function [{}]", target->getFullScopedName(ctx_)));
                record.symbolName = it->second->symbolName;
                record.addend     = 0;
                writeU64(textSection.data.bytes, patchOffset, 0);
                break;
            }

            case MicroRelocation::Kind::ForeignFunctionAddress:
            {
                const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
                if (!target)
                    return reportError("native backend encountered an invalid foreign relocation target");
                record.symbolName = target->resolveForeignFunctionName(ctx_);
                record.addend     = 0;
                writeU64(textSection.data.bytes, patchOffset, 0);
                break;
            }

            case MicroRelocation::Kind::ConstantAddress:
            {
                uint32_t shardIndex = 0;
                const Ref ref = compiler_.cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(relocation.targetAddress));
                if (ref == INVALID_REF)
                    return reportError("native backend cannot resolve constant relocation");
                record.symbolName = K_RDataBaseSymbol;
                record.addend     = rdataShardBaseOffsets_[shardIndex] + ref;
                writeU64(textSection.data.bytes, patchOffset, record.addend);
                break;
            }

            case MicroRelocation::Kind::GlobalInitAddress:
                record.symbolName = K_DataBaseSymbol;
                record.addend     = relocation.targetAddress;
                writeU64(textSection.data.bytes, patchOffset, record.addend);
                break;

            case MicroRelocation::Kind::GlobalZeroAddress:
                record.symbolName = K_BssBaseSymbol;
                record.addend     = relocation.targetAddress;
                writeU64(textSection.data.bytes, patchOffset, record.addend);
                break;

            case MicroRelocation::Kind::CompilerAddress:
                return reportError("native backend encountered a compiler segment relocation while emitting code");
        }

        textSection.relocations.push_back(record);
        return true;
    }

    bool NativeBackendBuilder::buildDataRelocations(CoffSectionBuild& section) const
    {
        for (const auto& relocation : section.data.relocations)
        {
            if (relocation.offset + sizeof(uint64_t) > section.data.bytes.size())
                return reportError("native backend data relocation offset is out of range");
            writeU64(section.data.bytes, relocation.offset, relocation.addend);
            section.relocations.push_back(relocation);
        }

        return true;
    }

    void NativeBackendBuilder::writeU64(std::vector<std::byte>& bytes, const uint32_t offset, const uint64_t value)
    {
        std::memcpy(bytes.data() + offset, &value, sizeof(value));
    }

    void NativeBackendBuilder::addDefinedSymbols(const NativeObjDescription& description,
                                                 const std::vector<CoffSectionBuild>& sections,
                                                 std::vector<CoffSymbolRecord>& symbols,
                                                 std::unordered_map<Utf8, uint32_t>& symbolIndices) const
    {
        const auto add = [&](CoffSymbolRecord record) {
            symbolIndices.emplace(record.name, static_cast<uint32_t>(symbols.size()));
            symbols.push_back(std::move(record));
        };

        if (description.startup)
        {
            add({
                .name          = description.startup->symbolName,
                .sectionNumber = static_cast<int16_t>(sections[0].sectionNumber),
                .value         = description.startup->textOffset,
                .type          = static_cast<uint16_t>(IMAGE_SYM_DTYPE_FUNCTION << 8),
                .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
            });
        }

        for (NativeFunctionInfo* info : description.functions)
        {
            if (!info)
                continue;
            add({
                .name          = info->symbolName,
                .sectionNumber = static_cast<int16_t>(sections[0].sectionNumber),
                .value         = info->textOffset,
                .type          = static_cast<uint16_t>(IMAGE_SYM_DTYPE_FUNCTION << 8),
                .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
            });
        }

        if (!description.includeData)
            return;

        for (const auto& section : sections)
        {
            if (section.data.name == ".rdata")
            {
                add({
                    .name          = K_RDataBaseSymbol,
                    .sectionNumber = static_cast<int16_t>(section.sectionNumber),
                    .value         = 0,
                    .type          = 0,
                    .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                });
            }
            else if (section.data.name == ".data")
            {
                add({
                    .name          = K_DataBaseSymbol,
                    .sectionNumber = static_cast<int16_t>(section.sectionNumber),
                    .value         = 0,
                    .type          = 0,
                    .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                });
            }
            else if (section.data.name == ".bss")
            {
                add({
                    .name          = K_BssBaseSymbol,
                    .sectionNumber = static_cast<int16_t>(section.sectionNumber),
                    .value         = 0,
                    .type          = 0,
                    .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                });
            }
        }
    }

    void NativeBackendBuilder::addUndefinedSymbols(const std::vector<CoffSectionBuild>& sections,
                                                   std::vector<CoffSymbolRecord>& symbols,
                                                   std::unordered_map<Utf8, uint32_t>& symbolIndices) const
    {
        for (const auto& section : sections)
        {
            for (const auto& relocation : section.relocations)
            {
                if (symbolIndices.contains(relocation.symbolName))
                    continue;

                symbolIndices.emplace(relocation.symbolName, static_cast<uint32_t>(symbols.size()));
                symbols.push_back({
                    .name          = relocation.symbolName,
                    .sectionNumber = 0,
                    .value         = 0,
                    .type          = 0,
                    .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                });
            }
        }
    }

    bool NativeBackendBuilder::flushCoffFile(const fs::path& objPath,
                                             std::vector<CoffSectionBuild>& sections,
                                             const std::vector<CoffSymbolRecord>& symbols,
                                             const std::unordered_map<Utf8, uint32_t>& symbolIndices) const
    {
        struct CoffStringTable
        {
            uint32_t add(const Utf8& name)
            {
                if (name.size() <= IMAGE_SIZEOF_SHORT_NAME)
                    return 0;
                if (const auto it = offsets.find(name); it != offsets.end())
                    return it->second;

                const uint32_t offset = size;
                offsets.emplace(name, offset);
                entries.push_back(name);
                size += static_cast<uint32_t>(name.size()) + 1;
                return offset;
            }

            uint32_t                     size = 4;
            std::unordered_map<Utf8, uint32_t> offsets;
            std::vector<Utf8>            entries;
        };

        CoffStringTable stringTable;
        for (const auto& symbol : symbols)
            stringTable.add(symbol.name);

        uint32_t fileOffset = sizeof(IMAGE_FILE_HEADER) + static_cast<uint32_t>(sections.size()) * sizeof(IMAGE_SECTION_HEADER);
        fileOffset          = Math::alignUpU32(fileOffset, 4);

        for (auto& section : sections)
        {
            if (!section.data.bss && !section.data.bytes.empty())
            {
                section.pointerToRawData = fileOffset;
                section.sizeOfRawData    = static_cast<uint32_t>(section.data.bytes.size());
                fileOffset += section.sizeOfRawData;
                fileOffset = Math::alignUpU32(fileOffset, 4);
            }
            else if (section.data.bss)
            {
                section.pointerToRawData = 0;
                section.sizeOfRawData    = section.data.bssSize;
            }

            if (!section.relocations.empty())
            {
                if (section.relocations.size() > 0xFFFFu)
                    return reportError("native backend emitted too many COFF relocations in one section");
                section.pointerToRelocations = fileOffset;
                section.numberOfRelocations  = static_cast<uint16_t>(section.relocations.size());
                fileOffset += static_cast<uint32_t>(section.relocations.size() * sizeof(IMAGE_RELOCATION));
                fileOffset = Math::alignUpU32(fileOffset, 4);
            }
        }

        const uint32_t symbolTableOffset = fileOffset;
        fileOffset += static_cast<uint32_t>(symbols.size() * sizeof(IMAGE_SYMBOL));
        const uint32_t stringTableOffset = fileOffset;
        fileOffset += stringTable.size;

        std::vector<std::byte> fileData(fileOffset, std::byte{0});

        IMAGE_FILE_HEADER header{};
        header.Machine              = IMAGE_FILE_MACHINE_AMD64;
        header.NumberOfSections     = static_cast<WORD>(sections.size());
        header.TimeDateStamp        = 0;
        header.PointerToSymbolTable = symbolTableOffset;
        header.NumberOfSymbols      = static_cast<DWORD>(symbols.size());
        header.SizeOfOptionalHeader = 0;
        header.Characteristics      = IMAGE_FILE_LARGE_ADDRESS_AWARE | IMAGE_FILE_DEBUG_STRIPPED;
        std::memcpy(fileData.data(), &header, sizeof(header));

        uint32_t sectionHeaderOffset = sizeof(IMAGE_FILE_HEADER);
        for (const auto& section : sections)
        {
            IMAGE_SECTION_HEADER headerSection{};
            std::memset(headerSection.Name, 0, sizeof(headerSection.Name));
            std::memcpy(headerSection.Name, section.data.name.data(), std::min<size_t>(section.data.name.size(), IMAGE_SIZEOF_SHORT_NAME));
            headerSection.SizeOfRawData      = section.sizeOfRawData;
            headerSection.PointerToRawData   = section.pointerToRawData;
            headerSection.PointerToRelocations = section.pointerToRelocations;
            headerSection.NumberOfRelocations = section.numberOfRelocations;
            headerSection.Characteristics    = section.data.characteristics;
            std::memcpy(fileData.data() + sectionHeaderOffset, &headerSection, sizeof(headerSection));
            sectionHeaderOffset += sizeof(IMAGE_SECTION_HEADER);
        }

        for (const auto& section : sections)
        {
            if (!section.data.bss && !section.data.bytes.empty())
                std::memcpy(fileData.data() + section.pointerToRawData, section.data.bytes.data(), section.data.bytes.size());

            if (section.relocations.empty())
                continue;

            uint32_t relocOffset = section.pointerToRelocations;
            for (const auto& relocation : section.relocations)
            {
                const auto it = symbolIndices.find(relocation.symbolName);
                if (it == symbolIndices.end())
                    return reportError(std::format("native backend cannot resolve COFF symbol [{}]", relocation.symbolName));

                IMAGE_RELOCATION relocRecord{};
                relocRecord.VirtualAddress   = relocation.offset;
                relocRecord.SymbolTableIndex = it->second;
                relocRecord.Type             = relocation.type;
                std::memcpy(fileData.data() + relocOffset, &relocRecord, sizeof(relocRecord));
                relocOffset += sizeof(IMAGE_RELOCATION);
            }
        }

        uint32_t symbolOffset = symbolTableOffset;
        for (const auto& symbol : symbols)
        {
            IMAGE_SYMBOL record{};
            if (symbol.name.size() <= IMAGE_SIZEOF_SHORT_NAME)
            {
                std::memcpy(record.N.ShortName, symbol.name.data(), symbol.name.size());
            }
            else
            {
                record.N.Name.Short = 0;
                record.N.Name.Long  = stringTable.offsets.at(symbol.name);
            }

            record.Value              = symbol.value;
            record.SectionNumber      = symbol.sectionNumber;
            record.Type               = symbol.type;
            record.StorageClass       = symbol.storageClass;
            record.NumberOfAuxSymbols = symbol.numAuxSymbols;
            std::memcpy(fileData.data() + symbolOffset, &record, sizeof(record));
            symbolOffset += sizeof(IMAGE_SYMBOL);
        }

        std::memcpy(fileData.data() + stringTableOffset, &stringTable.size, sizeof(uint32_t));
        uint32_t stringCursor = stringTableOffset + sizeof(uint32_t);
        for (const Utf8& entry : stringTable.entries)
        {
            std::memcpy(fileData.data() + stringCursor, entry.data(), entry.size());
            stringCursor += static_cast<uint32_t>(entry.size());
            fileData[stringCursor++] = std::byte{0};
        }

        std::ofstream file(objPath, std::ios::binary | std::ios::trunc);
        if (!file.is_open())
            return reportError(std::format("cannot open [{}] for writing", makeUtf8(objPath)));

        file.write(reinterpret_cast<const char*>(fileData.data()), static_cast<std::streamsize>(fileData.size()));
        if (!file.good())
            return reportError(std::format("cannot write [{}]", makeUtf8(objPath)));

        return true;
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
        NativeBackendBuilder builder(compiler, runArtifact);
        return builder.run();
    }
}

SWC_END_NAMESPACE();
