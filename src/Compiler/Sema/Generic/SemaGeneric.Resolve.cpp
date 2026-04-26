#include "pch.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void collectSymbolMapNamespacePath(const SymbolMap* symMap, SmallVector<IdentifierRef>& outPath)
    {
        SmallVector<IdentifierRef> reversedPath;
        for (const SymbolMap* current = symMap; current;)
        {
            const SymbolMap* owner = current->ownerSymMap();
            if (current->isNamespace() && (!owner || !owner->isModule()))
                reversedPath.push_back(current->idRef());

            const SymbolMap* next = owner;
            if (!next && current->isImpl())
            {
                const auto& impl = current->cast<SymbolImpl>();
                if (impl.isForStruct())
                    next = impl.symStruct()->ownerSymMap();
                else if (impl.isForEnum())
                    next = impl.symEnum()->ownerSymMap();
            }

            current = next;
        }

        outPath.clear();
        outPath.reserve(reversedPath.size());
        for (auto& it : std::views::reverse(reversedPath))
            outPath.push_back(it);
    }

    void appendCollectedGenericParam(Sema& sema, const AstNode& paramNode, AstNodeRef paramRef, SmallVector<SemaGeneric::GenericParamDesc>& outParams)
    {
        SemaGeneric::GenericParamDesc desc;
        desc.paramRef = paramRef;
        desc.idRef    = SemaHelpers::resolveIdentifier(sema, paramNode.codeRef());

        if (const auto* nodeType = paramNode.safeCast<AstGenericParamType>())
        {
            desc.kind       = SemaGeneric::GenericParamKind::Type;
            desc.defaultRef = nodeType->nodeAssignRef;
        }
        else
        {
            const auto& nodeValue = paramNode.cast<AstGenericParamValue>();
            desc.kind             = SemaGeneric::GenericParamKind::Value;
            desc.explicitType     = nodeValue.nodeTypeRef;
            desc.defaultRef       = nodeValue.nodeAssignRef;
        }

        outParams.push_back(desc);
    }
}

namespace SemaGeneric
{

    void collectGenericParams(Sema& sema, const AstNode& declNode, SpanRef spanRef, SmallVector<GenericParamDesc>& outParams)
    {
        outParams.clear();
        if (spanRef.isInvalid())
            return;

        const SourceView& srcView = sema.compiler().srcView(declNode.srcViewRef());
        const Ast&        ast     = srcView.file()->ast();

        SmallVector<AstNodeRef> params;
        ast.appendNodes(params, spanRef);
        outParams.reserve(params.size());

        for (const AstNodeRef paramRef : params)
            appendCollectedGenericParam(sema, ast.node(paramRef), paramRef, outParams);
    }

    void prepareGenericInstantiationContext(Sema& sema, SymbolMap* startSymMap, const SymbolImpl* impl, const SymbolInterface* itf, const AttributeList& attrs)
    {
        if (startSymMap)
            sema.startSymMap_ = startSymMap;

        SmallVector<IdentifierRef> nsPath;
        if (startSymMap)
            collectSymbolMapNamespacePath(startSymMap, nsPath);
        else
        {
            for (const IdentifierRef idRef : sema.frame().nsPath())
                nsPath.push_back(idRef);
        }
        const SymbolAccess access                  = sema.frame().currentAccess();
        const bool         globalCompilerIfEnabled = sema.frame().globalCompilerIfEnabled();

        sema.scopes_.clear();
        SemaScopeFlags scopeFlags = SemaScopeFlagsE::TopLevel;
        if (impl)
            scopeFlags.add(SemaScopeFlagsE::Impl);

        sema.scopes_.emplace_back(std::make_unique<SemaScope>(scopeFlags, nullptr));
        sema.curScope_ = sema.scopes_.back().get();
        sema.curScope_->setSymMap(sema.startSymMap_);

        sema.frames_.clear();
        sema.pushFrame({});
        for (const IdentifierRef idRef : nsPath)
            sema.frame().pushNs(idRef);
        sema.frame().setCurrentAccess(access);
        sema.frame().setGlobalCompilerIfEnabled(globalCompilerIfEnabled);
        sema.frame().setCurrentImpl(impl);
        sema.frame().setCurrentInterface(itf);
        sema.frame().currentAttributes() = attrs;
    }

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
            appendCollectedGenericParam(sema, sema.node(paramRef), paramRef, outParams);
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

        const SemaNodeView typeView = sema.viewNodeType(nodeRef);
        if (typeView.typeRef().isValid())
        {
            const TypeInfo& typeInfo = sema.typeMgr().get(typeView.typeRef());
            if (!sema.isValue(nodeRef) || typeInfo.isAggregate())
            {
                // Explicit type arguments only need the resolved type. Avoid forcing symbol payload
                // queries on complex type syntax such as quoted generic specializations or
                // anonymous aggregate type expressions.
                outArg.typeRef = typeView.typeRef();
                outArg.present = true;
                return Result::Continue;
            }
        }

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
