#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/SourceFile.h"
#include "Support/Math/Hash.h"
#include "Support/Math/Helpers.h"
#include "Support/Memory/Heap.h"
#include "Support/Report/Assert.h"
#if SWC_HAS_STATS
#endif

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isPublicApiSymbolAlphaNumeric(const char c)
    {
        return std::isalnum(static_cast<unsigned char>(c)) != 0;
    }

    Utf8 sanitizePublicApiSymbolText(const std::string_view text)
    {
        Utf8 out;
        bool lastWasUnderscore       = true;
        bool previousWasLowerOrDigit = false;
        for (const char c : text)
        {
            const auto uc = static_cast<unsigned char>(c);
            if (isPublicApiSymbolAlphaNumeric(c))
            {
                const bool isUpper = std::isupper(uc) != 0;
                const bool isLower = std::islower(uc) != 0;
                const bool isDigit = std::isdigit(uc) != 0;
                if (isUpper && !out.empty() && !lastWasUnderscore && previousWasLowerOrDigit)
                    out += '_';

                out += static_cast<char>(std::tolower(uc));
                lastWasUnderscore       = false;
                previousWasLowerOrDigit = isLower || isDigit;
                continue;
            }

            if (!lastWasUnderscore)
            {
                out += '_';
                lastWasUnderscore = true;
            }

            previousWasLowerOrDigit = false;
        }

        while (!out.empty() && out.back() == '_')
            out.pop_back();
        return out;
    }

    void appendPublicApiSymbolFragment(Utf8& out, const std::string_view text)
    {
        const Utf8 fragment = sanitizePublicApiSymbolText(text);
        if (fragment.empty())
            return;

        if (!out.empty() && out.back() != '_')
            out += '_';
        out += fragment;
    }

    void appendPublicApiTypeFragment(Utf8& out, const TaskContext& ctx, TypeRef typeRef);

    const SymbolNamespace* publicApiModuleNamespace(const TaskContext& ctx, const Symbol& symbol)
    {
        if (!symbol.srcViewRef().isValid())
            return nullptr;

        const SourceFile* sourceFile = ctx.compiler().srcView(symbol.srcViewRef()).file();
        return sourceFile ? sourceFile->moduleNamespace() : nullptr;
    }

    void appendPublicApiScopedSymbolPath(Utf8& out, const TaskContext& ctx, const Symbol& symbol, bool includeSymbol)
    {
        SmallVector8<const Symbol*> scopeChain;
        if (includeSymbol)
            scopeChain.push_back(&symbol);

        const SymbolNamespace* moduleNamespace = publicApiModuleNamespace(ctx, symbol);
        const SymbolMap*       scope           = symbol.ownerSymMap();
        while (scope)
        {
            if (scope != moduleNamespace && !scope->isModule() && !scope->isImpl())
                scopeChain.push_back(scope);
            scope = scope->ownerSymMap();
        }

        for (const Symbol* current : std::ranges::reverse_view(scopeChain))
        {
            if (!current)
                continue;
            appendPublicApiSymbolFragment(out, current->name(ctx));
        }
    }

    bool isPublicApiImplicitReceiverParam(const TaskContext& ctx, const SymbolVariable& param)
    {
        return param.idRef() == ctx.idMgr().predefined(IdentifierManager::PredefinedName::Me);
    }

    bool isFunctionNestedInFunctionScope(const SymbolFunction& symbol)
    {
        const SymbolMap* scope = symbol.ownerSymMap();
        while (scope)
        {
            if (scope->isFunction())
                return true;
            scope = scope->ownerSymMap();
        }

        return false;
    }

    void appendPublicApiGenericStructArgs(Utf8& out, const TaskContext& ctx, const SymbolStruct& instance)
    {
        SmallVector<GenericInstanceKey> args;
        if (!instance.tryGetGenericInstanceArgs(args))
            return;

        appendPublicApiSymbolFragment(out, "gen");
        for (const GenericInstanceKey& arg : args)
        {
            if (arg.typeRef.isValid())
            {
                appendPublicApiTypeFragment(out, ctx, arg.typeRef);
                continue;
            }

            if (arg.cstRef.isValid())
            {
                appendPublicApiSymbolFragment(out, ctx.cstMgr().get(arg.cstRef).toString(ctx).view());
                continue;
            }

            appendPublicApiSymbolFragment(out, "unknown");
        }
    }

    void appendPublicApiTypeFragment(Utf8& out, const TaskContext& ctx, TypeRef typeRef)
    {
        if (!typeRef.isValid())
        {
            appendPublicApiSymbolFragment(out, "invalid");
            return;
        }

        const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
        if (typeInfo.isNullable())
            appendPublicApiSymbolFragment(out, "nullable");
        if (typeInfo.isConst())
            appendPublicApiSymbolFragment(out, "const");

        switch (typeInfo.kind())
        {
            case TypeInfoKind::Bool:
                appendPublicApiSymbolFragment(out, "bool");
                return;
            case TypeInfoKind::Char:
                appendPublicApiSymbolFragment(out, "char");
                return;
            case TypeInfoKind::String:
                appendPublicApiSymbolFragment(out, "string");
                return;
            case TypeInfoKind::Void:
                appendPublicApiSymbolFragment(out, "void");
                return;
            case TypeInfoKind::Null:
                appendPublicApiSymbolFragment(out, "null");
                return;
            case TypeInfoKind::Undefined:
                appendPublicApiSymbolFragment(out, "undefined");
                return;
            case TypeInfoKind::Any:
                appendPublicApiSymbolFragment(out, "any");
                return;
            case TypeInfoKind::Rune:
                appendPublicApiSymbolFragment(out, "rune");
                return;
            case TypeInfoKind::CString:
                appendPublicApiSymbolFragment(out, "cstring");
                return;
            case TypeInfoKind::CodeBlock:
                appendPublicApiSymbolFragment(out, "code");
                appendPublicApiTypeFragment(out, ctx, typeInfo.payloadTypeRef());
                return;
            case TypeInfoKind::TypeInfo:
                appendPublicApiSymbolFragment(out, "typeinfo");
                return;
            case TypeInfoKind::AggregateStruct:
                appendPublicApiSymbolFragment(out, "struct_literal");
                return;
            case TypeInfoKind::AggregateArray:
                appendPublicApiSymbolFragment(out, "array_literal");
                return;
            case TypeInfoKind::Enum:
                appendPublicApiSymbolFragment(out, typeInfo.payloadSymEnum().getFullScopedName(ctx).view());
                return;
            case TypeInfoKind::Struct:
            {
                const SymbolStruct& instance = typeInfo.payloadSymStruct();
                const SymbolStruct* root     = instance.genericRootOrSelf();
                SWC_ASSERT(root != nullptr);
                appendPublicApiSymbolFragment(out, root->getFullScopedName(ctx).view());
                if (instance.isGenericInstance())
                    appendPublicApiGenericStructArgs(out, ctx, instance);
                return;
            }
            case TypeInfoKind::Interface:
                appendPublicApiSymbolFragment(out, typeInfo.payloadSymInterface().getFullScopedName(ctx).view());
                return;
            case TypeInfoKind::Alias:
                appendPublicApiSymbolFragment(out, typeInfo.payloadSymAlias().getFullScopedName(ctx).view());
                return;
            case TypeInfoKind::TypeValue:
                appendPublicApiSymbolFragment(out, "typeinfo");
                appendPublicApiTypeFragment(out, ctx, typeInfo.payloadTypeRef());
                return;
            case TypeInfoKind::ValuePointer:
                appendPublicApiSymbolFragment(out, "ptr");
                appendPublicApiTypeFragment(out, ctx, typeInfo.payloadTypeRef());
                return;
            case TypeInfoKind::BlockPointer:
                appendPublicApiSymbolFragment(out, "block_ptr");
                appendPublicApiTypeFragment(out, ctx, typeInfo.payloadTypeRef());
                return;
            case TypeInfoKind::Reference:
                appendPublicApiSymbolFragment(out, "ref");
                appendPublicApiTypeFragment(out, ctx, typeInfo.payloadTypeRef());
                return;
            case TypeInfoKind::MoveReference:
                appendPublicApiSymbolFragment(out, "move_ref");
                appendPublicApiTypeFragment(out, ctx, typeInfo.payloadTypeRef());
                return;
            case TypeInfoKind::Int:
            {
                if (typeInfo.payloadIntBits() == 0)
                {
                    appendPublicApiSymbolFragment(out, typeInfo.payloadIntSign() == TypeInfo::Sign::Unsigned ? "uint" : typeInfo.payloadIntSign() == TypeInfo::Sign::Signed ? "sint"
                                                                                                                                                                            : "int");
                    return;
                }

                const auto intName = std::format("{}{}", typeInfo.payloadIntSign() == TypeInfo::Sign::Unsigned ? "u" : "s", typeInfo.payloadIntBits());
                appendPublicApiSymbolFragment(out, intName);
                return;
            }
            case TypeInfoKind::Float:
            {
                if (typeInfo.payloadFloatBits() == 0)
                    appendPublicApiSymbolFragment(out, "float");
                else
                {
                    const auto floatName = std::format("f{}", typeInfo.payloadFloatBits());
                    appendPublicApiSymbolFragment(out, floatName);
                }
                return;
            }
            case TypeInfoKind::Slice:
                appendPublicApiSymbolFragment(out, "slice");
                appendPublicApiTypeFragment(out, ctx, typeInfo.payloadTypeRef());
                return;
            case TypeInfoKind::Array:
            {
                appendPublicApiSymbolFragment(out, "arr");
                if (typeInfo.payloadArrayDims().empty())
                {
                    appendPublicApiSymbolFragment(out, "unknown");
                }
                else
                {
                    for (const uint64_t dim : typeInfo.payloadArrayDims())
                    {
                        const auto dimText = std::to_string(dim);
                        appendPublicApiSymbolFragment(out, dimText);
                    }
                }

                appendPublicApiTypeFragment(out, ctx, typeInfo.payloadArrayElemTypeRef());
                return;
            }
            case TypeInfoKind::Variadic:
                appendPublicApiSymbolFragment(out, "variadic");
                return;
            case TypeInfoKind::TypedVariadic:
                appendPublicApiSymbolFragment(out, "typed_variadic");
                appendPublicApiTypeFragment(out, ctx, typeInfo.payloadTypeRef());
                return;
            case TypeInfoKind::Function:
            {
                const SymbolFunction& function = typeInfo.payloadSymFunction();
                appendPublicApiSymbolFragment(out, function.isMethod() ? "mtd" : "func");
                if (function.isClosure())
                    appendPublicApiSymbolFragment(out, "closure");
                if (function.parameters().empty())
                    appendPublicApiSymbolFragment(out, "void");
                else
                {
                    for (const SymbolVariable* param : function.parameters())
                    {
                        SWC_ASSERT(param != nullptr);
                        appendPublicApiTypeFragment(out, ctx, param->typeRef());
                    }
                }

                if (function.isConst())
                    appendPublicApiSymbolFragment(out, "const");
                if (function.hasVariadicParam())
                    appendPublicApiSymbolFragment(out, "variadic");
                if (function.isThrowable())
                    appendPublicApiSymbolFragment(out, "throw");
                if (function.callConvKind() != CallConvKind::Swag)
                {
                    appendPublicApiSymbolFragment(out, "cc");
                    appendPublicApiSymbolFragment(out, CallConv::get(function.callConvKind()).name);
                }

                appendPublicApiSymbolFragment(out, "ret");
                appendPublicApiTypeFragment(out, ctx, function.returnTypeRef());
                return;
            }

            default:
                appendPublicApiSymbolFragment(out, typeInfo.toName(ctx).view());
        }
    }

    void appendPublicApiFunctionScope(Utf8& out, const TaskContext& ctx, const SymbolFunction& symbol)
    {
        if (const SymbolStruct* ownerStruct = symbol.ownerStruct())
        {
            appendPublicApiScopedSymbolPath(out, ctx, *ownerStruct, true);
            return;
        }

        appendPublicApiScopedSymbolPath(out, ctx, symbol, false);
    }

    bool isPublicApiExportedOverload(const SymbolFunction& candidate)
    {
        return candidate.isPublic() && candidate.supportsPublicApiForeignExport();
    }

    void collectPublicApiOverloads(const SymbolFunction& symbol, const TaskContext& ctx, std::vector<const SymbolFunction*>& outOverloads)
    {
        SWC_UNUSED(ctx);
        outOverloads.clear();
        if (const SymbolStruct* ownerStruct = symbol.ownerStruct())
        {
            for (const SymbolFunction* candidate : ownerStruct->declaredMethods())
            {
                if (!candidate || candidate->idRef() != symbol.idRef())
                    continue;
                if (!isPublicApiExportedOverload(*candidate))
                    continue;

                outOverloads.push_back(candidate);
            }

            return;
        }

        const SymbolMap* ownerMap = symbol.ownerSymMap();
        if (!ownerMap)
            return;

        std::vector<const Symbol*> symbols;
        ownerMap->getAllSymbols(symbols);
        for (const Symbol* candidateBase : symbols)
        {
            const auto* candidate = candidateBase ? candidateBase->safeCast<SymbolFunction>() : nullptr;
            if (!candidate || candidate->idRef() != symbol.idRef())
                continue;
            if (!isPublicApiExportedOverload(*candidate))
                continue;

            outOverloads.push_back(candidate);
        }
    }

    bool publicApiNeedsOverloadSuffix(const SymbolFunction& symbol, const TaskContext& ctx)
    {
        std::vector<const SymbolFunction*> overloads;
        collectPublicApiOverloads(symbol, ctx, overloads);
        return overloads.size() > 1;
    }

    Utf8 buildPublicApiParameterSignature(const TaskContext& ctx, const SymbolFunction& symbol)
    {
        Utf8 result;
        bool hasExplicitParam = false;
        for (const SymbolVariable* param : symbol.parameters())
        {
            SWC_ASSERT(param != nullptr);
            if (isPublicApiImplicitReceiverParam(ctx, *param))
                continue;

            hasExplicitParam = true;
            appendPublicApiTypeFragment(result, ctx, param->typeRef());
        }

        if (!hasExplicitParam)
            appendPublicApiSymbolFragment(result, "void");
        return result;
    }

    Utf8 buildPublicApiImplicitReceiverSignature(const TaskContext& ctx, const SymbolFunction& symbol)
    {
        Utf8 result;
        for (const SymbolVariable* param : symbol.parameters())
        {
            SWC_ASSERT(param != nullptr);
            if (!isPublicApiImplicitReceiverParam(ctx, *param))
                continue;

            appendPublicApiTypeFragment(result, ctx, param->typeRef());
            break;
        }

        return result;
    }

    Utf8 buildPublicApiDetailedSignature(const TaskContext& ctx, const SymbolFunction& symbol)
    {
        Utf8       result         = buildPublicApiImplicitReceiverSignature(ctx, symbol);
        const Utf8 paramSignature = buildPublicApiParameterSignature(ctx, symbol);
        if (!paramSignature.empty())
            appendPublicApiSymbolFragment(result, paramSignature.view());

        if (symbol.isConst())
            appendPublicApiSymbolFragment(result, "const");
        if (symbol.hasVariadicParam())
            appendPublicApiSymbolFragment(result, "variadic");
        if (symbol.isThrowable())
            appendPublicApiSymbolFragment(result, "throw");
        if (symbol.callConvKind() != CallConvKind::Swag)
        {
            appendPublicApiSymbolFragment(result, "cc");
            appendPublicApiSymbolFragment(result, CallConv::get(symbol.callConvKind()).name);
        }

        appendPublicApiSymbolFragment(result, "ret");
        appendPublicApiTypeFragment(result, ctx, symbol.returnTypeRef());
        return result;
    }

    bool publicApiSignatureCollides(const SymbolFunction& symbol, const TaskContext& ctx, const Utf8& expectedSignature, const bool detailed)
    {
        std::vector<const SymbolFunction*> overloads;
        collectPublicApiOverloads(symbol, ctx, overloads);
        for (const SymbolFunction* candidate : overloads)
        {
            if (!candidate || candidate == &symbol)
                continue;

            const Utf8 candidateSignature = detailed ? buildPublicApiDetailedSignature(ctx, *candidate) : buildPublicApiParameterSignature(ctx, *candidate);
            if (candidateSignature == expectedSignature)
                return true;
        }

        return false;
    }

    void appendPublicApiOverloadSuffix(Utf8& out, const TaskContext& ctx, const SymbolFunction& symbol)
    {
        Utf8 signature = buildPublicApiParameterSignature(ctx, symbol);
        if (publicApiSignatureCollides(symbol, ctx, signature, false))
            signature = buildPublicApiDetailedSignature(ctx, symbol);

        out += "__";
        out += signature;
    }

    bool isLocalLayoutReady(TaskContext& ctx, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return false;

        const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
        if (typeInfo.isScalarUnsized() || typeInfo.isVoid() || typeInfo.isUndefined() || typeInfo.isAnyVariadic())
            return false;

        if (typeInfo.isArray())
        {
            if (typeInfo.payloadArrayDims().empty())
                return false;
            return isLocalLayoutReady(ctx, typeInfo.payloadArrayElemTypeRef());
        }

        if (typeInfo.isAggregate())
        {
            const auto& aggregateTypes = typeInfo.payloadAggregate().types;
            if (aggregateTypes.empty())
                return false;
            for (const TypeRef elemTypeRef : aggregateTypes)
            {
                if (!isLocalLayoutReady(ctx, elemTypeRef))
                    return false;
            }
        }

        if (typeInfo.isAlias())
            return isLocalLayoutReady(ctx, typeInfo.payloadSymAlias().underlyingTypeRef());

        if (typeInfo.isEnum())
            return isLocalLayoutReady(ctx, typeInfo.payloadSymEnum().underlyingTypeRef());

        if (typeInfo.isTypeValue())
            return isLocalLayoutReady(ctx, typeInfo.payloadTypeRef());

        return true;
    }

}

struct SymbolFunction::GenericData
{
    GenericInstanceStorage                        instances;
    std::atomic<const TaskContext*>               completionOwner = nullptr;
    mutable std::atomic<uint32_t>                 completionDepth = 0;
    mutable std::atomic<bool>                     nodeCompleted   = false;
    SymbolFunction*                               rootSym         = nullptr;
    std::shared_ptr<void>                         lazyGenericBodyRun;
    mutable std::recursive_mutex                  evalRunMutex;
    mutable std::shared_mutex                     evalCacheMutex;
    std::vector<SymbolInternal::GenericEvalEntry> evalCache;
};

RtAttributeFlags SymbolFunction::rtAttributeFlags() const
{
    if (rtAttributeBitIndex_ == K_INVALID_RT_ATTRIBUTE_BIT_INDEX)
        return RtAttributeFlagsE::Zero;

    return RtAttributeFlags{static_cast<RtAttributeFlagsE>(1ull << rtAttributeBitIndex_)};
}

void SymbolFunction::setRtAttributeFlags(const RtAttributeFlags attr)
{
    if (attr == RtAttributeFlagsE::Zero)
    {
        rtAttributeBitIndex_ = K_INVALID_RT_ATTRIBUTE_BIT_INDEX;
        return;
    }

    uint64_t bits = attr.get();
    SWC_ASSERT(bits != 0 && (bits & (bits - 1)) == 0);

    uint8_t bitIndex = 0;
    while ((bits & 1ull) == 0)
    {
        bits >>= 1;
        bitIndex++;
    }

    rtAttributeBitIndex_ = bitIndex;
}

Utf8 SymbolFunction::computeName(const TaskContext& ctx) const
{
    Utf8 out;
    out += hasExtraFlag(SymbolFunctionFlagsE::Method) ? "mtd" : "func";
    out += hasExtraFlag(SymbolFunctionFlagsE::Closure) ? "||" : "";
    out += "(";
    for (size_t i = 0; i < parameters_.size(); ++i)
    {
        if (i != 0)
            out += ", ";

        if (parameters_[i]->idRef().isValid())
        {
            out += parameters_[i]->name(ctx);
            out += ": ";
        }

        const TypeInfo& paramType = ctx.typeMgr().get(parameters_[i]->typeRef());
        out += paramType.toName(ctx);
    }
    out += ")";

    if (returnType_ != ctx.typeMgr().typeVoid())
    {
        out += "->";
        const TypeInfo& returnType = ctx.typeMgr().get(returnType_);
        out += returnType.toName(ctx);
    }

    out += hasExtraFlag(SymbolFunctionFlagsE::Throwable) ? " throw" : "";
    return out;
}

Utf8 SymbolFunction::computePublicApiSymbolName(const TaskContext& ctx) const
{
    Utf8 apiName;
    appendPublicApiFunctionScope(apiName, ctx, *this);
    appendPublicApiSymbolFragment(apiName, name(ctx));

    if (apiName.empty())
        apiName = "fn";
    if (publicApiNeedsOverloadSuffix(*this, ctx))
        appendPublicApiOverloadSuffix(apiName, ctx, *this);
    return apiName;
}

bool SymbolFunction::supportsGeneratedModuleApiExport() const noexcept
{
    if (!decl() || decl()->isNot(AstNodeId::FunctionDecl))
        return false;
    if (isAttribute() || isClosure() || isGenericRoot() || isGenericInstance() || hasUnmaterializedGenericBody())
        return false;
    if (hasExtraFlag(SymbolFunctionFlagsE::InlineLocalFunction))
        return false;
    if (isFunctionNestedInFunctionScope(*this))
        return false;
    if (attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
        return false;
    if (attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
        return false;
    if (const SymbolImpl* symImpl = declImplContext(); symImpl && !symImpl->isForStruct())
        return false;

    if (attributes().hasRtFlag(RtAttributeFlagsE::Macro) || attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        return true;

    if (!returnTypeRef().isValid())
        return false;

    for (const SymbolVariable* param : parameters())
    {
        if (!param || !param->typeRef().isValid())
            return false;
    }

    return true;
}

bool SymbolFunction::supportsPublicApiForeignExport() const noexcept
{
    return supportsGeneratedModuleApiExport() &&
           !attributes().hasRtFlag(RtAttributeFlagsE::Macro) &&
           !attributes().hasRtFlag(RtAttributeFlagsE::Mixin) &&
           decl()->safeCast<AstFunctionDecl>();
}

bool SymbolFunction::usesStructuralTypeIdentity() const noexcept
{
    return decl() && decl()->is(AstNodeId::LambdaType);
}

uint32_t SymbolFunction::typeSignatureHash() const noexcept
{
    if (!usesStructuralTypeIdentity())
        return Math::hashCombine(Math::hash(0), reinterpret_cast<uintptr_t>(this));

    uint32_t h = Math::hash(returnType_.get());
    h          = Math::hashCombine(h, static_cast<uint32_t>(callConvKind_));
    h          = Math::hashCombine(h, isClosure() ? 1u : 0u);
    h          = Math::hashCombine(h, isMethod() ? 1u : 0u);
    h          = Math::hashCombine(h, isThrowable() ? 1u : 0u);
    h          = Math::hashCombine(h, isConst() ? 1u : 0u);
    h          = Math::hashCombine(h, hasVariadicParam() ? 1u : 0u);
    h          = Math::hashCombine(h, static_cast<uint32_t>(parameters_.size()));
    for (const SymbolVariable* param : parameters_)
    {
        SWC_ASSERT(param != nullptr);
        h = Math::hashCombine(h, param->typeRef().get());
        h = Math::hashCombine(h, param->idRef().get());
    }

    return h;
}

bool SymbolFunction::sameTypeSignature(const SymbolFunction& otherFunc) const noexcept
{
    if (this == &otherFunc)
        return true;

    if (returnTypeRef() != otherFunc.returnTypeRef())
        return false;
    if (callConvKind() != otherFunc.callConvKind())
        return false;
    if (isClosure() != otherFunc.isClosure())
        return false;
    if (isMethod() != otherFunc.isMethod())
        return false;
    if (isThrowable() != otherFunc.isThrowable())
        return false;
    if (isConst() != otherFunc.isConst())
        return false;
    if (hasVariadicParam() != otherFunc.hasVariadicParam())
        return false;

    const auto& params1 = parameters();
    const auto& params2 = otherFunc.parameters();
    if (params1.size() != params2.size())
        return false;

    for (uint32_t i = 0; i < params1.size(); ++i)
    {
        SWC_ASSERT(params1[i] != nullptr);
        SWC_ASSERT(params2[i] != nullptr);
        if (params1[i]->typeRef() != params2[i]->typeRef())
            return false;
    }

    return true;
}

bool SymbolFunction::sameTypeSignatureIgnoringClosure(const SymbolFunction& otherFunc) const noexcept
{
    if (this == &otherFunc)
        return true;

    if (returnTypeRef() != otherFunc.returnTypeRef())
        return false;
    if (callConvKind() != otherFunc.callConvKind())
        return false;
    if (isMethod() != otherFunc.isMethod())
        return false;
    if (isThrowable() != otherFunc.isThrowable())
        return false;
    if (isConst() != otherFunc.isConst())
        return false;
    if (hasVariadicParam() != otherFunc.hasVariadicParam())
        return false;

    const auto& params1 = parameters();
    const auto& params2 = otherFunc.parameters();
    if (params1.size() != params2.size())
        return false;

    for (uint32_t i = 0; i < params1.size(); ++i)
    {
        SWC_ASSERT(params1[i] != nullptr);
        SWC_ASSERT(params2[i] != nullptr);
        if (params1[i]->typeRef() != params2[i]->typeRef())
            return false;
    }

    return true;
}

void SymbolFunction::setPure(bool value) noexcept
{
    if (value)
        addExtraFlag(SymbolFunctionFlagsE::Pure);
    else
        removeExtraFlag(SymbolFunctionFlagsE::Pure);
}

Utf8 SymbolFunction::resolveForeignFunctionName(const TaskContext& ctx) const
{
    if (!isForeign())
        return {};

    if (!foreignFunctionName().empty())
        return Utf8{foreignFunctionName()};

    return Utf8{name(ctx)};
}

void SymbolFunction::setExtraFlags(EnumFlags<AstFunctionFlagsE> parserFlags)
{
    if (parserFlags.has(AstFunctionFlagsE::Method))
        addExtraFlag(SymbolFunctionFlagsE::Method);
    if (parserFlags.has(AstFunctionFlagsE::Throwable))
        addExtraFlag(SymbolFunctionFlagsE::Throwable);
    if (parserFlags.has(AstFunctionFlagsE::Closure))
        addExtraFlag(SymbolFunctionFlagsE::Closure);
    if (parserFlags.has(AstFunctionFlagsE::Const))
        addExtraFlag(SymbolFunctionFlagsE::Const);
}

void SymbolFunction::addParameter(SymbolVariable* sym)
{
    SWC_ASSERT(sym != nullptr);
    sym->setParameterIndex(static_cast<uint32_t>(parameters_.size()));
    parameters_.push_back(sym);
}

bool SymbolFunction::tryGetParameterIndexByName(size_t& outIndex, const IdentifierRef name, const size_t startIndex) const noexcept
{
    for (size_t index = startIndex; index < parameters_.size(); ++index)
    {
        const SymbolVariable* param = parameters_[index];
        if (param && param->idRef() == name)
        {
            outIndex = index;
            return true;
        }
    }

    return false;
}

void SymbolFunction::setVariadicParamFlag(TaskContext& ctx)
{
    for (const SymbolVariable* param : parameters_)
    {
        const TypeRef typeRef = param->typeRef();
        SWC_ASSERT(typeRef.isValid());

        const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
        if (!typeInfo.isAnyVariadic())
            continue;

        addExtraFlag(SymbolFunctionFlagsE::Variadic);
        return;
    }
}

void SymbolFunction::addLocalVariable(TaskContext& ctx, SymbolVariable* sym)
{
    SWC_ASSERT(sym != nullptr);
    if (sym->isFunctionLocalVariable())
        return;

    sym->addExtraFlag(SymbolVariableFlagsE::FunctionLocal);
    if (!localVariableSet_.insert(sym).second)
        return;

    localVariables_.push_back(sym);
    while (numComputedLocals_ < localVariables_.size())
    {
        SymbolVariable* local = localVariables_[numComputedLocals_];
        SWC_ASSERT(local != nullptr);

        const TypeRef typeRef = local->typeRef();
        if (!isLocalLayoutReady(ctx, typeRef))
            return;
        if (SemaHelpers::usesCallerReturnStorage(ctx, *this, *local))
        {
            local->setOffset(0);
            numComputedLocals_++;
            continue;
        }

        const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
        const uint64_t  size      = typeInfo.sizeOf(ctx);
        const uint32_t  alignment = typeInfo.alignOf(ctx);
        SWC_ASSERT(size > 0);
        SWC_ASSERT(alignment > 0);

        localStackOffset_ = Math::alignUpU32(localStackOffset_, alignment);
        local->setOffset(localStackOffset_);
        SWC_ASSERT(size <= std::numeric_limits<uint32_t>::max() - localStackOffset_);
        localStackOffset_ += static_cast<uint32_t>(size);
        numComputedLocals_++;
    }
}

void SymbolFunction::addCallDependency(const SymbolFunction* sym)
{
    if (!sym || sym == this)
        return;
    if (sym->isForeign() || sym->isEmpty() || sym->isAttribute())
        return;
    if (sym->attributes().hasRtFlag(RtAttributeFlagsE::Macro) || sym->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        return;

    auto* const            mutableSym = const_cast<SymbolFunction*>(sym);
    const std::unique_lock lock(callDependenciesMutex_);
    if (!callDependencySet_.insert(mutableSym).second)
        return;
    callDependencies_.push_back(mutableSym);
}

void SymbolFunction::appendCallDependencies(SmallVector<SymbolFunction*>& out) const
{
    const std::shared_lock lock(callDependenciesMutex_);
    out.reserve(out.size() + callDependencies_.size());
    for (SymbolFunction* dep : callDependencies_)
        out.push_back(dep);
}

SymbolFunction::GenericData* SymbolFunction::genericData() const noexcept
{
    return genericData_.load(std::memory_order_acquire);
}

SymbolFunction::GenericData& SymbolFunction::ensureGenericData(const TaskContext& ctx) const noexcept
{
    if (auto* data = genericData())
        return *data;

    auto* newData  = heapNew<GenericData>();
    auto* expected = static_cast<GenericData*>(nullptr);
    if (!genericData_.compare_exchange_strong(expected, newData, std::memory_order_acq_rel, std::memory_order_acquire))
    {
        heapDelete(newData);
        return *expected;
    }

    SWC_UNUSED(ctx);
    return *newData;
}

GenericInstanceStorage& SymbolFunction::genericInstanceStorage(const TaskContext& ctx) const noexcept
{
    return ensureGenericData(ctx).instances;
}

bool SymbolFunction::tryGetGenericInstanceArgs(const TaskContext& ctx, const SymbolFunction& instance, SmallVector<GenericInstanceKey>& outArgs) const
{
    return genericInstanceStorage(ctx).tryGetArgs(instance, outArgs);
}

bool SymbolFunction::tryGetGenericInstanceArgs(const TaskContext& ctx, SmallVector<GenericInstanceKey>& outArgs) const
{
    if (!isGenericInstance())
        return false;

    const SymbolFunction* root = genericRootSym();
    SWC_ASSERT(root != nullptr);
    return root && root->tryGetGenericInstanceArgs(ctx, *this, outArgs);
}

std::shared_ptr<void>* SymbolFunction::lazyGenericBodyRunState() const noexcept
{
    auto* data = genericData();
    return data ? &data->lazyGenericBodyRun : nullptr;
}

std::shared_ptr<void>& SymbolFunction::ensureLazyGenericBodyRunState(const TaskContext& ctx) const noexcept
{
    return ensureGenericData(ctx).lazyGenericBodyRun;
}

AstNodeRef SymbolFunction::findGenericEvalNode(const TaskContext& ctx, const NodePayload* payloadContext, const Ast& ownerAst, const AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings) const
{
    const auto&            data = ensureGenericData(ctx);
    const std::shared_lock lock(data.evalCacheMutex);
    return SymbolInternal::findGenericEvalNode(data.evalCache, payloadContext, ownerAst, sourceRef, bindings);
}

void SymbolFunction::cacheGenericEvalNode(const TaskContext& ctx, const NodePayload* payloadContext, const Ast& ownerAst, const AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, const AstNodeRef evalRef) const
{
    if (sourceRef.isInvalid() || evalRef.isInvalid())
        return;

    auto&                  data = ensureGenericData(ctx);
    const std::unique_lock lock(data.evalCacheMutex);
    SymbolInternal::cacheGenericEvalNode(data.evalCache, payloadContext, ownerAst, sourceRef, bindings, evalRef);
}

std::recursive_mutex& SymbolFunction::genericEvalRunMutex(const TaskContext& ctx) const noexcept
{
    return ensureGenericData(ctx).evalRunMutex;
}

void SymbolFunction::setGenericCompletionOwner(const TaskContext& ctx) const noexcept
{
    auto&              data     = ensureGenericData(ctx);
    const TaskContext* expected = nullptr;
    const bool         done     = data.completionOwner.compare_exchange_strong(expected, &ctx, std::memory_order_acq_rel);
    SWC_ASSERT(done || expected == &ctx);
}

bool SymbolFunction::isGenericCompletionOwner(const TaskContext& ctx) const noexcept
{
    const auto* data = genericData();
    return data && data->completionOwner.load(std::memory_order_acquire) == &ctx;
}

bool SymbolFunction::isGenericCompletionActive(const TaskContext& ctx) const noexcept
{
    const auto* data = genericData();
    return data &&
           data->completionOwner.load(std::memory_order_acquire) == &ctx &&
           data->completionDepth.load(std::memory_order_acquire) != 0;
}

bool SymbolFunction::tryStartGenericCompletion(const TaskContext& ctx) const noexcept
{
    SWC_ASSERT(isGenericCompletionOwner(ctx));
    const auto* data = genericData();
    SWC_ASSERT(data != nullptr);
    const auto previousDepth = data->completionDepth.fetch_add(1, std::memory_order_acq_rel);
    if (previousDepth != 0)
    {
        data->completionDepth.fetch_sub(1, std::memory_order_acq_rel);
        return false;
    }

    return true;
}

void SymbolFunction::finishGenericCompletion() const noexcept
{
    const auto* data = genericData();
    SWC_ASSERT(data != nullptr);
    const auto previousDepth = data->completionDepth.fetch_sub(1, std::memory_order_acq_rel);
    SWC_ASSERT(previousDepth != 0);
}

bool SymbolFunction::isGenericNodeCompleted() const noexcept
{
    const auto* data = genericData();
    return data && data->nodeCompleted.load(std::memory_order_acquire);
}

void SymbolFunction::setGenericNodeCompleted() const noexcept
{
    const auto* data = genericData();
    SWC_ASSERT(data != nullptr);
    data->nodeCompleted.store(true, std::memory_order_release);
}

void SymbolFunction::setGenericRoot(bool value) noexcept
{
    if (value)
        addExtraFlag(SymbolFunctionFlagsE::GenericRoot);
    else
        removeExtraFlag(SymbolFunctionFlagsE::GenericRoot);
}

void SymbolFunction::setGenericInstance(const TaskContext& ctx, SymbolFunction* root) noexcept
{
    if (root)
    {
        addExtraFlag(SymbolFunctionFlagsE::GenericInstance);
        ensureGenericData(ctx).rootSym = root;
    }
    else
    {
        removeExtraFlag(SymbolFunctionFlagsE::GenericInstance);
        if (auto* data = genericData())
            data->rootSym = nullptr;
    }
}

bool SymbolFunction::hasUnmaterializedGenericBody() const noexcept
{
    if (isGenericRoot() && !isGenericInstance())
        return true;
    if (isGenericInstance())
        return false;

    const SymbolStruct* owner = ownerStruct();
    if (owner && owner->isGenericRoot() && !owner->isGenericInstance())
        return true;

    const SymbolImpl* symImpl = declImplContext();
    if (!symImpl)
        return false;

    if (symImpl->isForStruct())
    {
        const SymbolStruct* implStruct = symImpl->symStruct();
        return implStruct && implStruct->isGenericRoot() && !implStruct->isGenericInstance();
    }

    return false;
}

SymbolFunction* SymbolFunction::genericRootOrSelf() noexcept
{
    SymbolFunction* root = genericRootSym();
    SWC_ASSERT(root != nullptr || !isGenericInstance());
    return root ? root : this;
}

const SymbolFunction* SymbolFunction::genericRootOrSelf() const noexcept
{
    const SymbolFunction* root = genericRootSym();
    SWC_ASSERT(root != nullptr || !isGenericInstance());
    return root ? root : this;
}

SymbolFunction* SymbolFunction::genericRootSym() noexcept
{
    if (const auto* data = genericData())
        return data->rootSym;
    return nullptr;
}

const SymbolFunction* SymbolFunction::genericRootSym() const noexcept
{
    if (const auto* data = genericData())
        return data->rootSym;
    return nullptr;
}

const SymbolImpl* SymbolFunction::declImplContext() const noexcept
{
    const SymbolFunction* root   = genericRootSym();
    const SymbolMap*      symMap = (root ? root : this)->ownerSymMap();
    while (symMap)
    {
        if (symMap->isImpl())
            return &symMap->cast<SymbolImpl>();
        symMap = symMap->ownerSymMap();
    }

    return nullptr;
}

const SymbolInterface* SymbolFunction::declInterfaceContext() const noexcept
{
    const SymbolFunction* root   = genericRootSym();
    const SymbolMap*      symMap = (root ? root : this)->ownerSymMap();
    while (symMap)
    {
        if (symMap->isInterface())
            return &symMap->cast<SymbolInterface>();

        if (symMap->isImpl())
        {
            if (const SymbolInterface* itf = symMap->cast<SymbolImpl>().symInterface())
                return itf;
        }

        symMap = symMap->ownerSymMap();
    }

    return nullptr;
}

bool SymbolFunction::deepCompare(const SymbolFunction& otherFunc) const noexcept
{
    if (this == &otherFunc)
        return true;

    if (idRef() != otherFunc.idRef())
        return false;
    if (!sameTypeSignature(otherFunc))
        return false;
    if (semanticFlags() != otherFunc.semanticFlags())
        return false;
    if (rtAttributeFlags() != otherFunc.rtAttributeFlags())
        return false;

    return true;
}

SymbolStruct* SymbolFunction::ownerStruct()
{
    if (SymbolMap* symMap = ownerSymMap())
    {
        if (symMap->isImpl())
        {
            const auto& symImpl = symMap->cast<SymbolImpl>();
            if (symImpl.isForStruct())
                return symImpl.symStruct();
            return nullptr;
        }
        if (symMap->isStruct())
            return &symMap->cast<SymbolStruct>();
    }

    return nullptr;
}

const SymbolStruct* SymbolFunction::ownerStruct() const
{
    if (const SymbolMap* symMap = ownerSymMap())
    {
        if (symMap->isImpl())
        {
            const auto& symImpl = symMap->cast<SymbolImpl>();
            if (symImpl.isForStruct())
                return symImpl.symStruct();
            return nullptr;
        }
        if (symMap->isStruct())
            return &symMap->cast<SymbolStruct>();
    }

    return nullptr;
}

SWC_END_NAMESPACE();
