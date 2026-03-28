#pragma once
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGeneric
{
    enum class GenericParamKind : uint8_t
    {
        Type,
        Value,
    };

    struct GenericParamDesc
    {
        GenericParamKind kind         = GenericParamKind::Type;
        AstNodeRef       paramRef     = AstNodeRef::invalid();
        AstNodeRef       explicitType = AstNodeRef::invalid();
        AstNodeRef       defaultRef   = AstNodeRef::invalid();
        IdentifierRef    idRef        = IdentifierRef::invalid();
    };

    struct GenericResolvedArg
    {
        AstNodeRef  exprRef = AstNodeRef::invalid();
        TypeRef     typeRef = TypeRef::invalid();
        ConstantRef cstRef  = ConstantRef::invalid();
        bool        present = false;
    };

    struct GenericFunctionParamDesc
    {
        IdentifierRef idRef      = IdentifierRef::invalid();
        AstNodeRef    typeRef    = AstNodeRef::invalid();
        bool          isVariadic = false;
    };

    struct GenericCallArgEntry
    {
        AstNodeRef argRef = AstNodeRef::invalid();
    };

    TypeRef unwrapGenericDeductionType(TaskContext& ctx, TypeRef typeRef);

    void collectGenericParams(Sema& sema, SpanRef spanRef, std::vector<GenericParamDesc>& outParams);
    void appendResolvedGenericBinding(const GenericParamDesc& param, const GenericResolvedArg& arg, SmallVector<SemaClone::ParamBinding>& outBindings);
    void collectResolvedGenericBindings(const std::vector<GenericParamDesc>& params, const std::vector<GenericResolvedArg>& resolvedArgs, size_t count, SmallVector<SemaClone::ParamBinding>& outBindings);

    Result resolveGenericTypeArg(Sema& sema, AstNodeRef nodeRef, GenericResolvedArg& outArg);
    Result normalizeGenericConstantArg(Sema& sema, AstNodeRef nodeRef, GenericResolvedArg& outArg);
    Result resolveExplicitGenericArg(Sema& sema, const GenericParamDesc& param, AstNodeRef nodeRef, GenericResolvedArg& outArg);

    bool hasMissingGenericArgs(const std::vector<GenericResolvedArg>& resolvedArgs);

    Result deduceGenericFunctionArgs(Sema& sema, const SymbolFunction& root, const std::vector<GenericParamDesc>& genericParams, std::vector<GenericResolvedArg>& ioResolvedArgs, std::span<AstNodeRef> args, AstNodeRef ufcsArg);
    Result instantiateFunctionExplicit(Sema& sema, SymbolFunction& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolFunction*& outInstance);
    Result instantiateFunctionFromCall(Sema& sema, SymbolFunction& genericRoot, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SymbolFunction*& outInstance);
    Result instantiateStructExplicit(Sema& sema, SymbolStruct& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolStruct*& outInstance);
}

SWC_END_NAMESPACE();
