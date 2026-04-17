#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/ExternalModuleManager.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Math/ApFloat.h"
#include "Support/Math/ApsInt.h"
#include "Support/Core/Timer.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

bool CompilerInstance::dbgDevStop = false;

namespace
{
    uint64_t       g_RuntimeContextTlsId;
    std::once_flag g_RuntimeContextTlsIdOnce;

    template<typename T>
    bool appendUnique(std::vector<T*>& values, T* value)
    {
        if (std::ranges::find(values, value) != values.end())
            return false;

        values.push_back(value);
        return true;
    }

    bool shouldRegisterNativeFunction(const SymbolFunction& symbol)
    {
        return !symbol.isIgnored() &&
               !symbol.isForeign() &&
               !symbol.isEmpty() &&
               !symbol.isAttribute() &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Macro) &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Mixin) &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler);
    }

    bool isNativeRootFunction(const SymbolFunction& symbol)
    {
        const SymbolMap* owner = symbol.ownerSymMap();
        if (!owner)
            return false;

        while (owner->ownerSymMap())
            owner = owner->ownerSymMap();

        if (owner->isModule() || owner->isStruct() || owner->isInterface() || owner->isImpl())
            return true;

        return owner->isNamespace() && owner->idRef().isValid();
    }

    void initRuntimeContextTlsId()
    {
        g_RuntimeContextTlsId = Os::tlsAlloc();
    }

    uint64_t runtimeContextTlsId()
    {
        std::call_once(g_RuntimeContextTlsIdOnce, initRuntimeContextTlsId);
        return g_RuntimeContextTlsId;
    }

    Utf8 normalizePathForCompare(const fs::path& path)
    {
        Utf8 result{path.generic_string()};
#ifdef _WIN32
        result.make_lower();
#endif
        return result;
    }

    std::string_view trimView(std::string_view value)
    {
        while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front())))
            value.remove_prefix(1);
        while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back())))
            value.remove_suffix(1);
        return value;
    }

    Result reportInvalidCompilerTag(TaskContext& ctx, std::string_view rawTag, std::string_view because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_tag);
        diag.addArgument(Diagnostic::ARG_ARG, rawTag);
        diag.addArgument(Diagnostic::ARG_BECAUSE, because);
        diag.report(ctx);
        return Result::Error;
    }

    TypeRef compilerTagTypeByName(const TypeManager& typeMgr, std::string_view name)
    {
        if (name == "bool")
            return typeMgr.typeBool();
        if (name == "string")
            return typeMgr.typeString();
        if (name == "int")
            return typeMgr.typeIntSigned();
        if (name == "uint")
            return typeMgr.typeIntUnsigned();
        if (name == "s8")
            return typeMgr.typeS8();
        if (name == "u8")
            return typeMgr.typeU8();
        if (name == "s16")
            return typeMgr.typeS16();
        if (name == "u16")
            return typeMgr.typeU16();
        if (name == "s32")
            return typeMgr.typeS32();
        if (name == "u32")
            return typeMgr.typeU32();
        if (name == "s64")
            return typeMgr.typeS64();
        if (name == "u64")
            return typeMgr.typeU64();
        if (name == "f32")
            return typeMgr.typeF32();
        if (name == "f64")
            return typeMgr.typeF64();
        return TypeRef::invalid();
    }

    struct ParsedIntegerLiteral
    {
        bool     negative  = false;
        uint64_t magnitude = 0;
    };

    bool tryParseIntegerLiteral(std::string_view rawValue, ParsedIntegerLiteral& outValue, Utf8& outBecause)
    {
        outValue = {};
        rawValue = trimView(rawValue);
        if (rawValue.empty())
        {
            outBecause = "missing integer value";
            return false;
        }

        if (rawValue.front() == '+' || rawValue.front() == '-')
        {
            outValue.negative = rawValue.front() == '-';
            rawValue.remove_prefix(1);
        }

        if (rawValue.empty())
        {
            outBecause = "missing integer digits";
            return false;
        }

        uint32_t base = 10;
        if (rawValue.size() > 2 && rawValue[0] == '0' && (rawValue[1] == 'x' || rawValue[1] == 'X'))
        {
            base = 16;
            rawValue.remove_prefix(2);
        }
        else if (rawValue.size() > 2 && rawValue[0] == '0' && (rawValue[1] == 'b' || rawValue[1] == 'B'))
        {
            base = 2;
            rawValue.remove_prefix(2);
        }

        if (rawValue.empty())
        {
            outBecause = "missing integer digits";
            return false;
        }

        bool     hasDigit = false;
        uint64_t value    = 0;
        for (const char c : rawValue)
        {
            if (c == '_')
                continue;

            uint32_t digit = 0;
            if (c >= '0' && c <= '9')
                digit = static_cast<uint32_t>(c - '0');
            else if (c >= 'a' && c <= 'f')
                digit = 10u + static_cast<uint32_t>(c - 'a');
            else if (c >= 'A' && c <= 'F')
                digit = 10u + static_cast<uint32_t>(c - 'A');
            else
            {
                outBecause = "invalid integer literal";
                return false;
            }

            if (digit >= base)
            {
                outBecause = "invalid digit for integer base";
                return false;
            }

            hasDigit = true;
            if (value > (std::numeric_limits<uint64_t>::max() - digit) / base)
            {
                outBecause = "integer literal is too large";
                return false;
            }

            value = value * base + digit;
        }

        if (!hasDigit)
        {
            outBecause = "missing integer digits";
            return false;
        }

        outValue.magnitude = value;
        return true;
    }

    bool fitsUnsignedBits(const uint64_t value, const uint32_t bits)
    {
        if (!bits || bits >= 64)
            return true;
        return value <= ((uint64_t{1} << bits) - 1);
    }

    bool fitsSignedBits(const int64_t value, const uint32_t bits)
    {
        if (!bits || bits >= 64)
            return true;

        const int64_t minValue = -(int64_t{1} << (bits - 1));
        const int64_t maxValue = (int64_t{1} << (bits - 1)) - 1;
        return value >= minValue && value <= maxValue;
    }

    Result makeCompilerTagInteger(TaskContext& ctx, TypeRef typeRef, std::string_view rawValue, ConstantRef& outCstRef, Utf8& outBecause)
    {
        outCstRef = ConstantRef::invalid();

        ParsedIntegerLiteral literal;
        if (!tryParseIntegerLiteral(rawValue, literal, outBecause))
            return Result::Error;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        SWC_ASSERT(type.isInt());

        const uint32_t bits = type.payloadIntBits();
        if (type.isIntUnsigned())
        {
            if (literal.negative)
            {
                outBecause = "unsigned compiler tags cannot use a negative value";
                return Result::Error;
            }

            if (!fitsUnsignedBits(literal.magnitude, bits))
            {
                outBecause = "integer literal does not fit the requested type";
                return Result::Error;
            }

            const ApsInt value = bits ? ApsInt(literal.magnitude, bits) : ApsInt::makeUnsigned(literal.magnitude);
            outCstRef          = ctx.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, bits, TypeInfo::Sign::Unsigned));
            return Result::Continue;
        }

        int64_t signedValue = 0;
        if (literal.negative)
        {
            constexpr uint64_t minMagnitude = uint64_t{1} << 63;
            if (literal.magnitude > minMagnitude)
            {
                outBecause = "integer literal is too large";
                return Result::Error;
            }

            signedValue = literal.magnitude == minMagnitude ? std::numeric_limits<int64_t>::min() : -static_cast<int64_t>(literal.magnitude);
        }
        else
        {
            if (literal.magnitude > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()))
            {
                outBecause = "integer literal is too large";
                return Result::Error;
            }

            signedValue = static_cast<int64_t>(literal.magnitude);
        }

        if (!fitsSignedBits(signedValue, bits))
        {
            outBecause = "integer literal does not fit the requested type";
            return Result::Error;
        }

        const ApsInt value = bits ? ApsInt(signedValue, bits, false) : ApsInt::makeSigned(signedValue);
        outCstRef          = ctx.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, bits, TypeInfo::Sign::Signed));
        return Result::Continue;
    }

    Result makeCompilerTagFloat(TaskContext& ctx, TypeRef typeRef, std::string_view rawValue, ConstantRef& outCstRef, Utf8& outBecause)
    {
        outCstRef = ConstantRef::invalid();

        rawValue = trimView(rawValue);
        if (rawValue.empty())
        {
            outBecause = "missing floating-point value";
            return Result::Error;
        }

        std::string normalized;
        normalized.reserve(rawValue.size());
        for (const char c : rawValue)
        {
            if (c != '_')
                normalized.push_back(c);
        }

        if (normalized.empty())
        {
            outBecause = "missing floating-point value";
            return Result::Error;
        }

        char* endPtr = nullptr;
        errno        = 0;
        if (typeRef == ctx.typeMgr().typeF32())
        {
            const float value = std::strtof(normalized.c_str(), &endPtr);
            if (endPtr != normalized.data() + normalized.size() || errno == ERANGE)
            {
                outBecause = "invalid floating-point literal";
                return Result::Error;
            }

            if (!std::isfinite(value))
            {
                outBecause = "floating-point compiler tags must be finite";
                return Result::Error;
            }

            outCstRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, ApFloat(value), 32));
            return Result::Continue;
        }

        const double value = std::strtod(normalized.c_str(), &endPtr);
        if (endPtr != normalized.data() + normalized.size() || errno == ERANGE)
        {
            outBecause = "invalid floating-point literal";
            return Result::Error;
        }

        if (!std::isfinite(value))
        {
            outBecause = "floating-point compiler tags must be finite";
            return Result::Error;
        }

        outCstRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, ApFloat(value), 64));
        return Result::Continue;
    }

    Result makeCompilerTagValue(TaskContext& ctx, TypeRef typeRef, std::string_view rawValue, ConstantRef& outCstRef, Utf8& outBecause)
    {
        outCstRef = ConstantRef::invalid();
        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isBool())
        {
            rawValue = trimView(rawValue);
            if (rawValue == "true")
            {
                outCstRef = ctx.cstMgr().cstTrue();
                return Result::Continue;
            }

            if (rawValue == "false")
            {
                outCstRef = ctx.cstMgr().cstFalse();
                return Result::Continue;
            }

            outBecause = "boolean compiler tags must be 'true' or 'false'";
            return Result::Error;
        }

        if (type.isString())
        {
            outCstRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, trimView(rawValue)));
            return Result::Continue;
        }

        if (type.isInt())
            return makeCompilerTagInteger(ctx, typeRef, rawValue, outCstRef, outBecause);
        if (type.isFloat())
            return makeCompilerTagFloat(ctx, typeRef, rawValue, outCstRef, outBecause);

        outBecause = std::format("unsupported compiler tag type '{}'", type.toName(ctx));
        return Result::Error;
    }

    Result parseOneCompilerTag(TaskContext& ctx, std::string_view rawTag, CompilerInstance::CompilerTag& outTag)
    {
        rawTag = trimView(rawTag);
        if (rawTag.empty())
            return reportInvalidCompilerTag(ctx, rawTag, "missing tag name");

        outTag       = {};
        outTag.source = rawTag;

        const size_t equalPos = rawTag.find('=');
        if (equalPos == std::string_view::npos)
        {
            const std::string_view name = trimView(rawTag);
            if (name.empty())
                return reportInvalidCompilerTag(ctx, rawTag, "missing tag name");

            outTag.name  = name;
            outTag.cstRef = ctx.cstMgr().cstTrue();
            return Result::Continue;
        }

        const std::string_view leftPart  = trimView(rawTag.substr(0, equalPos));
        const std::string_view rightPart = trimView(rawTag.substr(equalPos + 1));
        if (leftPart.empty())
            return reportInvalidCompilerTag(ctx, rawTag, "missing tag name");
        if (rightPart.empty())
            return reportInvalidCompilerTag(ctx, rawTag, "missing tag value");

        std::string_view namePart = leftPart;
        std::string_view typePart;
        if (const size_t colonPos = leftPart.find(':'); colonPos != std::string_view::npos)
        {
            namePart = trimView(leftPart.substr(0, colonPos));
            typePart = trimView(leftPart.substr(colonPos + 1));
        }

        if (namePart.empty())
            return reportInvalidCompilerTag(ctx, rawTag, "missing tag name");

        outTag.name = namePart;

        if (typePart.empty())
        {
            if (rightPart == "true")
            {
                outTag.cstRef = ctx.cstMgr().cstTrue();
                return Result::Continue;
            }

            if (rightPart == "false")
            {
                outTag.cstRef = ctx.cstMgr().cstFalse();
                return Result::Continue;
            }

            Utf8       because;
            ConstantRef cstRef = ConstantRef::invalid();
            if (makeCompilerTagInteger(ctx, ctx.typeMgr().typeS32(), rightPart, cstRef, because) != Result::Continue)
            {
                if (because.empty())
                    because = "compiler tags without an explicit type must be boolean or default to s32 integers";
                return reportInvalidCompilerTag(ctx, rawTag, because);
            }

            outTag.cstRef = cstRef;
            return Result::Continue;
        }

        const TypeRef typeRef = compilerTagTypeByName(ctx.typeMgr(), typePart);
        if (typeRef.isInvalid())
            return reportInvalidCompilerTag(ctx, rawTag, std::format("unsupported compiler tag type '{}'", typePart));

        Utf8       because;
        ConstantRef cstRef = ConstantRef::invalid();
        if (makeCompilerTagValue(ctx, typeRef, rightPart, cstRef, because) != Result::Continue)
            return reportInvalidCompilerTag(ctx, rawTag, because);

        outTag.cstRef = cstRef;
        return Result::Continue;
    }

    void addInternalCompilerTags(TaskContext& ctx, std::vector<CompilerInstance::CompilerTag>& outTags)
    {
        CompilerInstance::CompilerTag tag;
        tag.name   = "Swag.Endian";
        tag.source = "<internal>";

        switch (ctx.cmdLine().targetArch)
        {
            case Runtime::TargetArch::X86_64:
                tag.cstRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, "little"));
                outTags.push_back(std::move(tag));
                return;
        }

        SWC_UNREACHABLE();
    }

    Result setupCompilerTags(TaskContext& ctx, std::vector<CompilerInstance::CompilerTag>& outTags)
    {
        outTags.clear();
        outTags.reserve(1 + ctx.cmdLine().tags.size());
        addInternalCompilerTags(ctx, outTags);

        for (const Utf8& rawTag : ctx.cmdLine().tags)
        {
            CompilerInstance::CompilerTag tag;
            SWC_RESULT(parseOneCompilerTag(ctx, rawTag.view(), tag));
            outTags.push_back(std::move(tag));
        }

        return Result::Continue;
    }

    void collectSwagFilesRec(const CommandLine& cmdLine, const fs::path& folder, std::vector<fs::path>& files, bool canFilter = true)
    {
        std::error_code ec;
        for (fs::recursive_directory_iterator it(folder, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
            {
                ec.clear();
                continue;
            }

            const fs::directory_entry& entry = *it;
            if (!entry.is_regular_file(ec))
            {
                ec.clear();
                continue;
            }

            const fs::path&   path = entry.path();
            const std::string ext  = path.extension().string();
            if (ext != ".swg" && ext != ".swgs")
                continue;

            if (canFilter && !cmdLine.fileFilter.empty())
            {
                const std::string pathString = path.string();
                bool              ignore     = false;
                for (const Utf8& filter : cmdLine.fileFilter)
                {
                    if (!pathString.contains(filter))
                    {
                        ignore = true;
                        break;
                    }
                }

                if (ignore)
                    continue;
            }

            files.push_back(path);
        }
    }

    const Runtime::CompilerMessage* runtimeCompilerGetMessage(const CompilerInstance* owner)
    {
        SWC_ASSERT(owner != nullptr);
        return &owner->runtimeCompilerMessage();
    }

    Runtime::BuildCfg* runtimeCompilerGetBuildCfg(CompilerInstance* owner)
    {
        SWC_ASSERT(owner != nullptr);
        return &owner->buildCfg();
    }

    void runtimeCompilerCompileString(const CompilerInstance* owner, Runtime::String str)
    {
        SWC_ASSERT(owner != nullptr);
        const TaskContext ctx(owner->global(), owner->cmdLine());
        Logger::print(ctx, std::string_view(str.ptr, str.length));
    }
}

CompilerInstance::CompilerInstance(const Global& global, const CommandLine& cmdLine) :
    cmdLine_(&cmdLine),
    global_(&global),
    buildCfg_(cmdLine.defaultBuildCfg)
{
    (void) runtimeContextTlsId();

    jobClientId_ = global.jobMgr().newClientId();
    exeFullName_ = Os::getExeFullName();

    const uint32_t numWorkers     = global.jobMgr().numWorkers();
    const uint32_t perThreadSlots = global.jobMgr().isSingleThreaded() ? 1 : numWorkers + 1;
    perThreadData_.resize(perThreadSlots);
    jitMemMgr_         = std::make_unique<JITMemoryManager>();
    jitExecMgr_        = std::make_unique<JITExecManager>();
    externalModuleMgr_ = std::make_unique<ExternalModuleManager>();
    setupRuntimeCompiler();
}

CompilerInstance::~CompilerInstance()
{
    // SymbolFunction instances are arena-allocated, so their JITMemory destructors do not reliably
    // run during compiler teardown. Unregister prepared function tables before executable pages are
    // released or stale Windows unwind entries can survive into the next compiler instance.
    resetPreparedJitFunctions();
}

std::byte* CompilerInstance::dataSegmentAddress(const DataSegmentKind kind, const uint32_t offset)
{
    switch (kind)
    {
        case DataSegmentKind::GlobalZero:
            return globalZeroSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::GlobalInit:
            return globalInitSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Compiler:
            return compilerSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Zero:
            return constantSegment_.ptr<std::byte>(offset);
    }

    SWC_UNREACHABLE();
}

const std::byte* CompilerInstance::dataSegmentAddress(const DataSegmentKind kind, const uint32_t offset) const
{
    switch (kind)
    {
        case DataSegmentKind::GlobalZero:
            return globalZeroSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::GlobalInit:
            return globalInitSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Compiler:
            return compilerSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Zero:
            return constantSegment_.ptr<std::byte>(offset);
    }

    SWC_UNREACHABLE();
}

Result CompilerInstance::setupSema(TaskContext& ctx)
{
    typeMgr_ = std::make_unique<TypeManager>();
    typeGen_ = std::make_unique<TypeGen>();
    cstMgr_  = std::make_unique<ConstantManager>();
    idMgr_   = std::make_unique<IdentifierManager>();

    idMgr_->setup(ctx);
    typeMgr_->setup(ctx);
    cstMgr_->setup(ctx);
    compilerTags_.clear();
    SWC_RESULT(setupCompilerTags(ctx, compilerTags_));
    return Result::Continue;
}

uint32_t CompilerInstance::pendingImplRegistrations() const
{
    return pendingImplRegistrations_.load(std::memory_order_relaxed);
}

void CompilerInstance::incPendingImplRegistrations()
{
    pendingImplRegistrations_.fetch_add(1, std::memory_order_relaxed);
    notifyAlive();
}

void CompilerInstance::decPendingImplRegistrations()
{
    const uint32_t prev = pendingImplRegistrations_.fetch_sub(1, std::memory_order_relaxed);
    SWC_ASSERT(prev > 0);
    notifyAlive();
}

void CompilerInstance::logBefore()
{
    const TaskContext ctx(*this);
    ctx.global().logger().resetStageClaims();
    TimedActionLog::printSessionFlags(ctx);
}

void CompilerInstance::logAfter()
{
    const TaskContext ctx(*this);
    TimedActionLog::printSummary(ctx);
}

void CompilerInstance::logStats()
{
    if (!cmdLine().stats && !cmdLine().statsMem)
        return;

    const TaskContext ctx(*this);
    Stats::get().print(ctx);
}

void CompilerInstance::processCommand()
{
    const Timer time(&Stats::get().timeTotal);
    if (cmdLine().verboseInfo)
        Command::verboseInfo(*this);

    switch (cmdLine().command)
    {
        case CommandKind::Syntax:
            Command::syntax(*this);
            break;
        case CommandKind::Sema:
            Command::sema(*this);
            break;
        case CommandKind::Test:
            Command::test(*this);
            break;
        case CommandKind::Build:
            Command::build(*this);
            break;
        case CommandKind::Run:
            Command::run(*this);
            break;
        default:
            SWC_UNREACHABLE();
    }
}

void CompilerInstance::setupRuntimeCompiler()
{
    runtimeCompiler_.obj      = this;
    runtimeCompiler_.itable   = runtimeCompilerITable_;
    runtimeCompilerITable_[0] = nullptr;
    runtimeCompilerITable_[1] = reinterpret_cast<void*>(&runtimeCompilerGetMessage);
    runtimeCompilerITable_[2] = reinterpret_cast<void*>(&runtimeCompilerGetBuildCfg);
    runtimeCompilerITable_[3] = reinterpret_cast<void*>(&runtimeCompilerCompileString);
}

uint64_t* CompilerInstance::runtimeContextTlsIdStorage()
{
    (void) runtimeContextTlsId();
    return &g_RuntimeContextTlsId;
}

Runtime::Context* CompilerInstance::runtimeContextFromTls()
{
    return static_cast<Runtime::Context*>(Os::tlsGetValue(runtimeContextTlsId()));
}

void CompilerInstance::setRuntimeContextForCurrentThread(Runtime::Context* context)
{
    Os::tlsSetValue(runtimeContextTlsId(), context);
}

uint32_t CompilerInstance::nativeRuntimeContextTlsIdOffset()
{
    std::call_once(nativeRuntimeContextTlsIdOffsetOnce_, [this] {
        const auto [offset, storage]     = globalZeroSegment_.reserve<uint64_t>();
        nativeRuntimeContextTlsIdOffset_ = offset;
        *storage                         = runtimeContextTlsId() + 1;
    });

    SWC_ASSERT(nativeRuntimeContextTlsIdOffset_ != UINT32_MAX);
    return nativeRuntimeContextTlsIdOffset_;
}

void CompilerInstance::initPerThreadRuntimeContextForJit()
{
    PerThreadData& td              = perThreadData_[JobManager::threadIndex()];
    td.runtimeContext.runtimeFlags = Runtime::RuntimeFlags::FromCompiler;
    setRuntimeContextForCurrentThread(&td.runtimeContext);

    if (nativeRuntimeContextTlsIdOffset_ != UINT32_MAX)
    {
        uint64_t* const tlsStorage = globalZeroSegment_.ptr<uint64_t>(nativeRuntimeContextTlsIdOffset_);
        SWC_ASSERT(tlsStorage != nullptr);
        *tlsStorage = runtimeContextTlsId() + 1;
    }
}

void CompilerInstance::registerNativeCodeFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;
    if (!isNativeRootFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted = appendUnique(nativeCodeSegment_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeTestFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeTestFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeInitFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeInitFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativePreMainFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativePreMainFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeDropFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeDropFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeMainFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeMainFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeGlobalVariable(SymbolVariable* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!symbol->hasGlobalStorage())
        return;
    if (symbol->globalStorageKind() == DataSegmentKind::Compiler)
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted = appendUnique(nativeGlobalVariables_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeGlobalFunctionInitTarget(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted = appendUnique(nativeGlobalFunctionInitTargets_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerPreparedJitFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);

    const std::unique_lock lock(mutex_);
    appendUnique(jitPreparedFunctions_, symbol);
}

void CompilerInstance::resetPreparedJitFunctions()
{
    std::vector<SymbolFunction*> preparedFunctions;
    {
        const std::unique_lock lock(mutex_);
        preparedFunctions.swap(jitPreparedFunctions_);
    }

    for (SymbolFunction* function : preparedFunctions)
    {
        if (function)
            function->resetJitState();
    }
}

std::vector<SymbolFunction*> CompilerInstance::nativeGlobalFunctionInitTargetsSnapshot() const
{
    const std::shared_lock lock(mutex_);
    return nativeGlobalFunctionInitTargets_;
}

std::vector<SymbolVariable*> CompilerInstance::nativeGlobalVariablesSnapshot() const
{
    const std::shared_lock lock(mutex_);
    return nativeGlobalVariables_;
}

std::vector<SymbolFunction*> CompilerInstance::jitPreparedFunctionsSnapshot() const
{
    const std::shared_lock lock(mutex_);
    return jitPreparedFunctions_;
}

ExitCode CompilerInstance::run()
{
    logBefore();
    processCommand();
    logAfter();
    logStats();
    return Stats::getNumErrors() > 0 ? ExitCode::CompileError : ExitCode::Success;
}

SourceView& CompilerInstance::addSourceView()
{
    const std::unique_lock lock(mutex_);
    auto                   srcViewRef = static_cast<SourceViewRef>(static_cast<uint32_t>(srcViews_.size()));
    srcViews_.emplace_back(std::make_unique<SourceView>(srcViewRef, nullptr));
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::addSourceView(FileRef fileRef)
{
    SWC_ASSERT(fileRef.isValid());
    SWC_RACE_CONDITION_READ(rcFiles_);

    const std::unique_lock lock(mutex_);
    auto                   srcViewRef = static_cast<SourceViewRef>(static_cast<uint32_t>(srcViews_.size()));
    srcViews_.emplace_back(std::make_unique<SourceView>(srcViewRef, &file(fileRef)));
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::srcView(SourceViewRef ref)
{
    const std::shared_lock lock(mutex_);
    SWC_ASSERT(ref.get() < srcViews_.size());

    SourceView* const view = srcViews_[ref.get()].get();
    return *(view);
}

const SourceView& CompilerInstance::srcView(SourceViewRef ref) const
{
    const std::shared_lock lock(mutex_);
    SWC_ASSERT(ref.get() < srcViews_.size());

    const SourceView* const view = srcViews_[ref.get()].get();
    return *(view);
}

const SourceView* CompilerInstance::findSourceViewByFileName(const std::string_view fileName) const
{
    if (fileName.empty())
        return nullptr;

    const fs::path wantedPath{std::string(fileName)};
    const Utf8     wantedPathNormalized = normalizePathForCompare(wantedPath);

    const std::shared_lock lock(mutex_);
    for (const std::unique_ptr<SourceView>& srcViewPtr : srcViews_)
    {
        const SourceView* const srcView = srcViewPtr.get();
        if (!srcView)
            continue;

        const SourceFile* sourceFile = srcView->file();
        if (!sourceFile)
            continue;

        if (normalizePathForCompare(sourceFile->path()) == wantedPathNormalized)
            return srcView;
    }

    return nullptr;
}

bool CompilerInstance::setMainFunc(AstCompilerFunc* node)
{
    const std::unique_lock lock(mutex_);
    if (mainFunc_)
        return false;
    mainFunc_ = node;
    return true;
}

bool CompilerInstance::markNativeOutputsCleared()
{
    return !nativeOutputsCleared_.exchange(true, std::memory_order_acq_rel);
}

bool CompilerInstance::registerForeignLib(std::string_view name)
{
    const std::unique_lock lock(mutex_);
    for (const Utf8& lib : foreignLibs_)
    {
        if (lib == name)
            return false;
    }

    foreignLibs_.emplace_back(name);
    return true;
}

const CompilerInstance::CompilerTag* CompilerInstance::findCompilerTag(std::string_view name) const
{
    for (const CompilerTag& tag : compilerTags_)
    {
        if (std::string_view{tag.name} == name)
            return &tag;
    }

    return nullptr;
}

void CompilerInstance::registerRuntimeFunctionSymbol(const IdentifierRef idRef, SymbolFunction* symbol)
{
    SWC_ASSERT(idRef.isValid());
    SWC_ASSERT(symbol != nullptr);

    bool                   inserted = false;
    const std::unique_lock lock(mutex_);
    const auto             it = runtimeFunctionSymbols_.find(idRef);
    if (it == runtimeFunctionSymbols_.end())
    {
        runtimeFunctionSymbols_.emplace(idRef, symbol);
        inserted = true;
    }
    else if (it->second == nullptr)
    {
        it->second = symbol;
        inserted   = true;
    }

    if (inserted)
        notifyAlive();
}

SymbolFunction* CompilerInstance::runtimeFunctionSymbol(const IdentifierRef idRef) const
{
    const std::shared_lock lock(mutex_);
    const auto             it = runtimeFunctionSymbols_.find(idRef);
    if (it == runtimeFunctionSymbols_.end())
        return nullptr;
    return it->second;
}

bool CompilerInstance::tryRegisterReportedDiagnostic(const std::string_view message)
{
    const std::scoped_lock lock(reportedDiagnosticsMutex_);
    return reportedDiagnostics_.insert(Utf8{message}).second;
}

void CompilerInstance::registerInMemoryFile(fs::path path, const std::string_view content)
{
    if (!path.is_absolute())
        path = fs::absolute(path);

    path = path.lexically_normal();

    const std::unique_lock lock(mutex_);
    inMemoryFiles_[normalizePathForCompare(path)] = Utf8(content);
}

SourceFile& CompilerInstance::addFile(fs::path path, FileFlags flags)
{
    if (!path.is_absolute())
        path = fs::absolute(path);

    return addResolvedFile(path.lexically_normal(), flags);
}

SourceFile& CompilerInstance::addResolvedFile(fs::path path, FileFlags flags)
{
    SWC_RACE_CONDITION_WRITE(rcFiles_);
    SWC_ASSERT(path.is_absolute());
    path = path.lexically_normal();

    auto fileRef = static_cast<FileRef>(static_cast<uint32_t>(files_.size()));
    files_.emplace_back(std::make_unique<SourceFile>(fileRef, std::move(path), flags));
    filePtrs_.push_back(files_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    fileRef.dbgPtr = files_.back().get();
#endif

    const Utf8 key = normalizePathForCompare(files_.back()->path());
    {
        const std::shared_lock lock(mutex_);
        const auto             it = inMemoryFiles_.find(key);
        if (it != inMemoryFiles_.end())
            files_.back()->setContent(it->second.view());
    }

    return *files_.back();
}

std::span<SourceFile* const> CompilerInstance::files() const
{
    SWC_RACE_CONDITION_READ(rcFiles_);
    return filePtrs_;
}

void CompilerInstance::appendResolvedFiles(std::vector<fs::path>& paths, FileFlags flags)
{
    if (paths.empty())
        return;

    files_.reserve(files_.size() + paths.size());
    filePtrs_.reserve(filePtrs_.size() + paths.size());
    for (fs::path& path : paths)
        addResolvedFile(std::move(path), flags);
}

void CompilerInstance::collectFolderFiles(const fs::path& folder, FileFlags flags, const bool canFilter)
{
    std::vector<fs::path> paths;
    collectSwagFilesRec(cmdLine(), folder, paths, canFilter);
    std::ranges::sort(paths);
    appendResolvedFiles(paths, flags);
}

Result CompilerInstance::collectFiles(TaskContext& ctx)
{
    const CommandLine& cmdLine = ctx.cmdLine();

    // Collect direct folders from the command line
    for (const fs::path& folder : cmdLine.directories)
        collectFolderFiles(folder, FileFlagsE::CustomSrc, true);

    // Collect direct files from the command line
    if (!cmdLine.files.empty())
    {
        files_.reserve(files_.size() + cmdLine.files.size());
        filePtrs_.reserve(filePtrs_.size() + cmdLine.files.size());
        for (const fs::path& file : cmdLine.files)
            addResolvedFile(file, FileFlagsE::CustomSrc);
    }

    // Collect files for the module
    if (!cmdLine.modulePath.empty())
    {
        modulePathFile_ = cmdLine.modulePath / "module.swg";
        SWC_RESULT(FileSystem::resolveFile(ctx, modulePathFile_));
        addResolvedFile(modulePathFile_, FileFlagsE::Module);

        modulePathSrc_ = cmdLine.modulePath / "src";
        SWC_RESULT(FileSystem::resolveFolder(ctx, modulePathSrc_));
        collectFolderFiles(modulePathSrc_, FileFlagsE::ModuleSrc, true);
    }

    // Collect runtime files
    if (cmdLine.runtime)
    {
        fs::path runtimePath = exeFullName_.parent_path() / "Runtime";
        SWC_RESULT(FileSystem::resolveFolder(ctx, runtimePath));
        collectFolderFiles(runtimePath, FileFlagsE::Runtime, false);
    }

    srcViews_.reserve(files_.size());

    if (files_.empty())
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
