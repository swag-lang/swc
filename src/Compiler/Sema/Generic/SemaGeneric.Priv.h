#pragma once
#include <memory>
#include "Compiler/Sema/Generic/GenericInstanceStorage.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Support/Core/SmallVector.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class Symbol;
class SymbolFunction;
class SymbolStruct;
struct AstFunctionDecl;
struct AstNode;
struct CastFailure;

namespace SemaGeneric::Internal
{
    struct ResolvedGenericBindingSource
    {
        std::span<const GenericParamDesc> params;
        std::span<const GenericResolvedArg> resolvedArgs;
    };

    struct FunctionWhereInputs
    {
        SmallVector<SemaClone::ParamBinding> bindings;
        Utf8                                 bindingText;
    };

    const AstFunctionDecl* genericFunctionDecl(const SymbolFunction& root);
    const AstNode*         genericStructDeclNode(const SymbolStruct& root);
    SpanRef                genericStructParamSpan(const SymbolStruct& root);
    SpanRef                genericStructWhereSpan(const SymbolStruct& root);
    SpanRef                genericParamSpan(const Symbol& root);
    bool                   hasGenericParams(const Symbol& root);
    AstNodeRef             genericDeclNodeRef(const Symbol& root);

    void buildGenericCloneBindings(std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, SmallVector<SemaClone::ParamBinding>& outBindings);
    void buildGenericCloneBindings(const ResolvedGenericBindingSource& source, SmallVector<SemaClone::ParamBinding>& outBindings);

    bool loadFunctionInstanceGenericArgs(Sema& sema, const SymbolFunction& function, SmallVector<GenericParamDesc>& outParams, SmallVector<GenericInstanceKey>& outArgs);
    bool loadOwnerStructGenericArgs(Sema& sema, const SymbolFunction& function, SmallVector<GenericParamDesc>& outParams, SmallVector<GenericInstanceKey>& outArgs);
    void collectAmbientGenericFunctions(const Sema& sema, SmallVector<const SymbolFunction*>& outFunctions);

    Sema* tryCreateSemaForGenericDecl(Sema& sema, const Symbol& root, std::unique_ptr<Sema>& ownedSema);
    Sema* tryCreateSemaForSymbolDecl(Sema& sema, const Symbol& symbol, std::unique_ptr<Sema>& ownedSema);

    void buildResolvedGenericContextBindings(Sema& sema, const Symbol& root, const ResolvedGenericBindingSource& source, SmallVector<SemaClone::ParamBinding>& outBindings);
    void buildPartialGenericContextBindings(Sema& sema, const Symbol& root, const ResolvedGenericBindingSource& source, size_t count, SmallVector<SemaClone::ParamBinding>& outBindings);
    Utf8 formatResolvedGenericBindings(Sema& sema, const ResolvedGenericBindingSource& source);
    void buildFunctionWhereInputs(Sema& sema, const SymbolFunction& function, FunctionWhereInputs& outInputs);
    void buildFunctionWhereInputs(Sema& sema, const SymbolFunction& function, const ResolvedGenericBindingSource& source, FunctionWhereInputs& outInputs);

    Result runGenericNode(Sema& sema, const Symbol& root, AstNodeRef nodeRef);
    Result runGenericInstanceNode(Sema& sema, const Symbol& root, Symbol& instance);
    Result evalGenericConstraintNode(Sema& sema, const Symbol& root, AstNodeRef constraintRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outEvalRef);
    Result evalGenericClonedNode(Sema& sema, const Symbol& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outClonedRef);
    Result instantiateGenericStructImpls(Sema& sema, const SymbolStruct& root, SymbolStruct& instance, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs);

    Result checkFunctionWhereConstraints(Sema& sema, bool& outSatisfied, const SymbolFunction& function, std::span<const SemaClone::ParamBinding> bindings, const Utf8& bindingText, CastFailure* outFailure, AstNodeRef errorNodeRef);
    Result validateGenericStructWhereConstraints(Sema& sema, const SymbolStruct& root, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, AstNodeRef errorNodeRef);
}

SWC_END_NAMESPACE();
