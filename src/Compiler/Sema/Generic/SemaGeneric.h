#pragma once
#include "Compiler/Sema/Generic/GenericInstanceStorage.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/SmallVector.h"
#include "Support/Core/Utf8.h"
#include <memory>
#include <string_view>

SWC_BEGIN_NAMESPACE();

class Sema;
class Symbol;
class SymbolMap;
class SymbolImpl;
class SymbolInterface;
class SymbolFunction;
class SymbolStruct;
struct AstFunctionDecl;
struct AstNode;
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
        IdentifierRef idRef           = IdentifierRef::invalid();
        AstNodeRef    typeRef         = AstNodeRef::invalid();
        TypeRef       resolvedTypeRef = TypeRef::invalid();
        AstNodeRef    defaultRef      = AstNodeRef::invalid();
        bool          isVariadic      = false;
        bool          hasExplicitType = false;
    };

    struct GenericCallArgEntry
    {
        AstNodeRef argRef                      = AstNodeRef::invalid();
        uint32_t   callArgIndex                = 0;
        bool       allowImplicitAddressBinding = false;
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

    Result evalGenericFunctionParamDefault(Sema& sema, const SymbolFunction& root, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, AstNodeRef defaultRef, AstNodeRef& outClonedRef);
    void   collectFunctionParamDescs(Sema& sema, const SymbolFunction& function, SmallVector<GenericFunctionParamDesc>& outParams);
    Result deduceGenericFunctionArgs(Sema& sema, const SymbolFunction& root, std::span<const GenericParamDesc> genericParams, SmallVector<GenericResolvedArg>& ioResolvedArgs, std::span<AstNodeRef> args, AstNodeRef ufcsArg, CastFailure* outFailure = nullptr, uint32_t* outFailureArgIndex = nullptr);
    Result resolveFunctionCallParamType(Sema& sema, const SymbolFunction& function, AstNodeRef calleeRef, std::span<AstNodeRef> args, AstNodeRef ufcsArg, AstNodeRef childRef, TypeRef& outTypeRef, bool requireCompleteGenericArgs = false);
    Result evaluateFunctionWhereConstraints(Sema& sema, bool& outSatisfied, const SymbolFunction& function, CastFailure* outFailure = nullptr);
    Result instantiateFunctionExplicit(Sema& sema, SymbolFunction& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolFunction*& outInstance);
    Result instantiateFunctionFromCall(Sema& sema, SymbolFunction& genericRoot, std::span<AstNodeRef> args, AstNodeRef ufcsArg, std::span<const AstNodeRef> explicitGenericArgNodes, SymbolFunction*& outInstance, CastFailure* outFailure = nullptr, uint32_t* outFailureArgIndex = nullptr);
    Result instantiateStructExplicit(Sema& sema, SymbolStruct& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolStruct*& outInstance);
    Result instantiateStructFromContext(Sema& sema, SymbolStruct& genericRoot, SymbolStruct*& outInstance);

    namespace Internal
    {
        struct ResolvedGenericBindingSource
        {
            std::span<const GenericParamDesc>   params;
            std::span<const GenericResolvedArg> resolvedArgs;
        };

        struct FunctionWhereInputs
        {
            SmallVector<SemaClone::ParamBinding> bindings;
            Utf8                                 bindingText;
        };

        enum class GenericEvalReadyKind : uint8_t
        {
            Constant,
            TypeOrSymbol,
        };

        const AstFunctionDecl* genericFunctionDecl(const SymbolFunction& root);
        const AstNode*         genericStructDeclNode(const SymbolStruct& root);
        SpanRef                genericStructParamSpan(const SymbolStruct& root);
        bool                   loadStructInstanceGenericArgs(Sema& sema, const SymbolStruct& instance, SmallVector<GenericParamDesc>& outParams, SmallVector<GenericInstanceKey>& outArgs);
        AstNodeRef             genericDeclNodeRef(const Symbol& root);
        bool                   loadFunctionInstanceGenericArgs(Sema& sema, const SymbolFunction& function, SmallVector<GenericParamDesc>& outParams, SmallVector<GenericInstanceKey>& outArgs);
        bool                   loadOwnerStructGenericArgs(Sema& sema, const SymbolFunction& function, SmallVector<GenericParamDesc>& outParams, SmallVector<GenericInstanceKey>& outArgs);
        void                   collectAmbientGenericFunctions(const Sema& sema, SmallVector<const SymbolFunction*>& outFunctions);
        Utf8                   formatResolvedGenericArg(Sema& sema, const GenericResolvedArg& arg);
        Utf8                   formatGenericInstanceKey(Sema& sema, const GenericInstanceKey& key);
        void                   appendFormattedBinding(Utf8& out, std::string_view name, const Utf8& value);
        Utf8                   formatResolvedGenericBindings(Sema& sema, const ResolvedGenericBindingSource& source);
        Utf8                   formatGenericInstanceBindings(Sema& sema, std::span<const GenericParamDesc> params, std::span<const GenericInstanceKey> args);

        Sema* tryCreateSemaForGenericDecl(Sema& sema, const Symbol& root, std::unique_ptr<Sema>& ownedSema);

        void buildResolvedGenericContextBindings(Sema& sema, const Symbol& root, const ResolvedGenericBindingSource& source, SmallVector<SemaClone::ParamBinding>& outBindings);
        void buildPartialGenericContextBindings(Sema& sema, const Symbol& root, const ResolvedGenericBindingSource& source, size_t count, SmallVector<SemaClone::ParamBinding>& outBindings);
        void buildFunctionWhereInputs(Sema& sema, const SymbolFunction& function, FunctionWhereInputs& outInputs);
        void buildFunctionWhereInputs(Sema& sema, const SymbolFunction& function, const ResolvedGenericBindingSource& source, FunctionWhereInputs& outInputs);

        Result runGenericInstanceNode(Sema& sema, const Symbol& root, Symbol& instance);
        Result evalGenericConstraintNode(Sema& sema, const Symbol& root, AstNodeRef constraintRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outEvalRef);
        Result evalGenericClonedNode(Sema& sema, const Symbol& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, GenericEvalReadyKind readyKind, AstNodeRef& outClonedRef);
        Result instantiateGenericStructImpls(Sema& sema, const SymbolStruct& root, SymbolStruct& instance, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs);

        Result checkFunctionWhereConstraints(Sema& sema, bool& outSatisfied, const SymbolFunction& function, std::span<const SemaClone::ParamBinding> bindings, const Utf8& bindingText, CastFailure* outFailure, AstNodeRef errorNodeRef);
        Result validateGenericStructWhereConstraints(Sema& sema, const SymbolStruct& root, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, AstNodeRef errorNodeRef);
    }
}

SWC_END_NAMESPACE();
