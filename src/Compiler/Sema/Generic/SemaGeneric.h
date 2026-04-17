#pragma once
#include "Compiler/Sema/Helpers/SemaClone.h"

SWC_BEGIN_NAMESPACE();

class SymbolMap;
class SymbolImpl;
class SymbolInterface;
class SymbolFunction;
class SymbolStruct;
struct AttributeList;
struct CastFailure;

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
        AstNodeRef  exprRef      = AstNodeRef::invalid();
        AstNodeRef  diagRef      = AstNodeRef::invalid();
        TypeRef     typeRef      = TypeRef::invalid();
        ConstantRef cstRef       = ConstantRef::invalid();
        uint32_t    callArgIndex = UINT32_MAX;
        bool        present      = false;
    };

    struct GenericFunctionParamDesc
    {
        IdentifierRef idRef      = IdentifierRef::invalid();
        AstNodeRef    typeRef    = AstNodeRef::invalid();
        bool          isVariadic = false;
    };

    struct GenericCallArgEntry
    {
        AstNodeRef argRef       = AstNodeRef::invalid();
        uint32_t   callArgIndex = 0;
    };

    TypeRef unwrapGenericDeductionType(TaskContext& ctx, TypeRef typeRef);
    void    prepareGenericInstantiationContext(Sema& sema, SymbolMap* startSymMap, const SymbolImpl* impl, const SymbolInterface* itf, const AttributeList& attrs);

    void collectGenericParams(Sema& sema, SpanRef spanRef, SmallVector<GenericParamDesc>& outParams);
    void collectGenericParams(Sema& sema, const AstNode& declNode, SpanRef spanRef, SmallVector<GenericParamDesc>& outParams);
    void appendResolvedGenericBinding(const GenericParamDesc& param, const GenericResolvedArg& arg, SmallVector<SemaClone::ParamBinding>& outBindings);
    void collectResolvedGenericBindings(std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, size_t count, SmallVector<SemaClone::ParamBinding>& outBindings);

    Result resolveGenericTypeArg(Sema& sema, AstNodeRef nodeRef, GenericResolvedArg& outArg);
    Result normalizeGenericConstantArg(Sema& sema, AstNodeRef nodeRef, GenericResolvedArg& outArg);
    Result resolveExplicitGenericArg(Sema& sema, const GenericParamDesc& param, AstNodeRef nodeRef, GenericResolvedArg& outArg);

    bool hasMissingGenericArgs(std::span<const GenericResolvedArg> resolvedArgs);

    Result deduceGenericFunctionArgs(Sema& sema, const SymbolFunction& root, std::span<const GenericParamDesc> genericParams, SmallVector<GenericResolvedArg>& ioResolvedArgs, std::span<AstNodeRef> args, AstNodeRef ufcsArg, CastFailure* outFailure = nullptr, uint32_t* outFailureArgIndex = nullptr);
    Result evaluateFunctionWhereConstraints(Sema& sema, bool& outSatisfied, const SymbolFunction& function, CastFailure* outFailure = nullptr);
    Result instantiateFunctionExplicit(Sema& sema, SymbolFunction& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolFunction*& outInstance);
    Result instantiateFunctionFromCall(Sema& sema, SymbolFunction& genericRoot, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SymbolFunction*& outInstance, CastFailure* outFailure = nullptr, uint32_t* outFailureArgIndex = nullptr);
    Result instantiateStructExplicit(Sema& sema, SymbolStruct& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolStruct*& outInstance);
    Result instantiateStructFromContext(Sema& sema, SymbolStruct& genericRoot, SymbolStruct*& outInstance);
}

SWC_END_NAMESPACE();
