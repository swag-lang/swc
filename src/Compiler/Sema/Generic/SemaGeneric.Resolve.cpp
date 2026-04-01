#include "pch.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGeneric
{
    TypeRef unwrapGenericDeductionType(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
            const TypeRef   unwrapped = typeInfo.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias | TypeExpandE::Enum);
            if (!unwrapped.isValid() || unwrapped == typeRef)
                return typeRef;
            typeRef = unwrapped;
        }

        return typeRef;
    }

    void collectGenericParams(Sema& sema, SpanRef spanRef, SmallVector<GenericParamDesc>& outParams)
    {
        outParams.clear();
        if (spanRef.isInvalid())
            return;

        SmallVector<AstNodeRef> params;
        sema.ast().appendNodes(params, spanRef);
        outParams.reserve(params.size());

        for (const AstNodeRef paramRef : params)
        {
            const AstNode& paramNode = sema.node(paramRef);

            GenericParamDesc desc;
            desc.paramRef = paramRef;
            desc.idRef    = SemaHelpers::resolveIdentifier(sema, paramNode.codeRef());

            if (const auto* nodeType = paramNode.safeCast<AstGenericParamType>())
            {
                desc.kind       = GenericParamKind::Type;
                desc.defaultRef = nodeType->nodeAssignRef;
            }
            else
            {
                const auto& nodeValue = paramNode.cast<AstGenericParamValue>();
                desc.kind             = GenericParamKind::Value;
                desc.explicitType     = nodeValue.nodeTypeRef;
                desc.defaultRef       = nodeValue.nodeAssignRef;
            }

            outParams.push_back(desc);
        }
    }

    void appendResolvedGenericBinding(const GenericParamDesc& param, const GenericResolvedArg& arg, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        if (!arg.present)
            return;

        SemaClone::ParamBinding binding;
        binding.idRef = param.idRef;
        if (param.kind == GenericParamKind::Type)
        {
            binding.exprRef = arg.exprRef;
            if (binding.exprRef.isInvalid())
                binding.typeRef = arg.typeRef;
        }
        else
        {
            binding.exprRef = arg.exprRef;
            binding.typeRef = arg.typeRef;
            binding.cstRef  = arg.cstRef;
        }

        outBindings.push_back(binding);
    }

    void collectResolvedGenericBindings(std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, size_t count, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        outBindings.clear();
        const size_t n = std::min(count, params.size());
        outBindings.reserve(n);
        for (size_t i = 0; i < n; ++i)
            appendResolvedGenericBinding(params[i], resolvedArgs[i], outBindings);
    }

    Result resolveGenericTypeArg(Sema& sema, AstNodeRef nodeRef, GenericResolvedArg& outArg)
    {
        outArg = {};

        const SemaNodeView view = sema.viewNodeTypeSymbol(nodeRef);
        if (view.sym() && view.sym()->isType())
        {
            TypeRef typeRef = view.typeRef();
            if (!typeRef.isValid())
                typeRef = view.sym()->typeRef();
            if (!typeRef.isValid())
                return SemaError::raise(sema, DiagnosticId::sema_err_not_type, nodeRef);

            outArg.typeRef = typeRef;
            outArg.present = true;
            return Result::Continue;
        }

        if (view.typeRef().isValid() && !sema.isValue(nodeRef))
        {
            // Explicit type arguments must be self-contained for nested generic
            // instantiations. Keep the resolved type, not the original syntax node,
            // otherwise an inner clone can accidentally reintroduce outer bindings.
            outArg.typeRef = view.typeRef();
            outArg.present = true;
            return Result::Continue;
        }

        return SemaError::raise(sema, DiagnosticId::sema_err_not_type, nodeRef);
    }

    Result normalizeGenericConstantArg(Sema& sema, AstNodeRef nodeRef, GenericResolvedArg& outArg)
    {
        const SemaNodeView view = sema.viewNodeTypeConstant(nodeRef);
        if (!view.cstRef().isValid())
            return SemaError::raiseExprNotConst(sema, nodeRef);

        outArg         = {};
        outArg.exprRef = nodeRef;
        outArg.typeRef = view.typeRef();
        outArg.cstRef  = view.cstRef();
        outArg.present = true;

        if (outArg.typeRef.isValid())
        {
            const TypeInfo& typeInfo = sema.typeMgr().get(outArg.typeRef);
            if (typeInfo.isScalarUnsized() && outArg.cstRef.isValid())
            {
                ConstantRef newCstRef = ConstantRef::invalid();
                SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, nodeRef, outArg.cstRef, TypeInfo::Sign::Unknown));
                if (newCstRef.isValid())
                {
                    sema.setConstant(nodeRef, newCstRef);
                    outArg.cstRef  = newCstRef;
                    outArg.typeRef = sema.cstMgr().get(newCstRef).typeRef();
                }
            }
        }

        return Result::Continue;
    }

    Result resolveExplicitGenericArg(Sema& sema, const GenericParamDesc& param, AstNodeRef nodeRef, GenericResolvedArg& outArg)
    {
        if (param.kind == GenericParamKind::Type)
            return resolveGenericTypeArg(sema, nodeRef, outArg);
        return normalizeGenericConstantArg(sema, nodeRef, outArg);
    }

    bool hasMissingGenericArgs(std::span<const GenericResolvedArg> resolvedArgs)
    {
        for (const auto& arg : resolvedArgs)
        {
            if (!arg.present)
                return true;
        }

        return false;
    }
}

SWC_END_NAMESPACE();
