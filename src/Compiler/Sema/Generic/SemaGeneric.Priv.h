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

    Sema* tryCreateSemaForGenericDecl(Sema& sema, const Symbol& root, std::unique_ptr<Sema>& ownedSema);

    void buildResolvedGenericContextBindings(Sema& sema, const Symbol& root, const ResolvedGenericBindingSource& source, SmallVector<SemaClone::ParamBinding>& outBindings);
    void buildPartialGenericContextBindings(Sema& sema, const Symbol& root, const ResolvedGenericBindingSource& source, size_t count, SmallVector<SemaClone::ParamBinding>& outBindings);
    void buildFunctionWhereInputs(Sema& sema, const SymbolFunction& function, FunctionWhereInputs& outInputs);
    void buildFunctionWhereInputs(Sema& sema, const SymbolFunction& function, const ResolvedGenericBindingSource& source, FunctionWhereInputs& outInputs);

    Result runGenericInstanceNode(Sema& sema, const Symbol& root, Symbol& instance);
    Result evalGenericConstraintNode(Sema& sema, const Symbol& root, AstNodeRef constraintRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outEvalRef);
    Result evalGenericClonedNode(Sema& sema, const Symbol& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outClonedRef);
    Result instantiateGenericStructImpls(Sema& sema, const SymbolStruct& root, SymbolStruct& instance, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs);

    Result checkFunctionWhereConstraints(Sema& sema, bool& outSatisfied, const SymbolFunction& function, std::span<const SemaClone::ParamBinding> bindings, const Utf8& bindingText, CastFailure* outFailure, AstNodeRef errorNodeRef);
    Result validateGenericStructWhereConstraints(Sema& sema, const SymbolStruct& root, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, AstNodeRef errorNodeRef);
}

SWC_END_NAMESPACE();
