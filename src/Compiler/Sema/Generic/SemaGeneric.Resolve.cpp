#include "pch.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    SymbolStruct* resolveGenericRootStructAlias(Symbol* symbol)
    {
        Symbol* current = symbol;
        while (current && current->isAlias())
        {
            auto& alias = current->cast<SymbolAlias>();
            if (alias.isStrict())
                return nullptr;

            const auto* next = alias.aliasedSymbol();
            if (!next || next == current)
                return nullptr;

            current = const_cast<Symbol*>(next);
        }

        if (!current || !current->isStruct())
            return nullptr;

        auto& st = current->cast<SymbolStruct>();
        return st.isGenericRoot() && !st.isGenericInstance() ? &st : nullptr;
    }

    SymbolStruct* genericRootStructFromExplicitTypeArg(Sema& sema, AstNodeRef nodeRef, TypeRef typeRef)
    {
        const SemaNodeView view = sema.viewNodeTypeSymbol(nodeRef);
        if (auto* genericRoot = resolveGenericRootStructAlias(view.sym()))
            return genericRoot;

        TypeRef representedTypeRef = TypeRef::invalid();
        if (typeRef.isValid())
        {
            const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
            if (typeInfo.isTypeValue())
                representedTypeRef = typeInfo.payloadTypeRef();
            else if (typeInfo.isStruct())
                representedTypeRef = typeRef;
        }

        if (!representedTypeRef.isValid())
            return nullptr;

        Symbol* representedSym = sema.typeMgr().get(representedTypeRef).getSymbol();
        return resolveGenericRootStructAlias(representedSym);
    }

    Result specializeExplicitGenericTypeArgFromContext(Sema& sema, AstNodeRef nodeRef, TypeRef& ioTypeRef)
    {
        auto* genericRoot = genericRootStructFromExplicitTypeArg(sema, nodeRef, ioTypeRef);
        if (!genericRoot)
            return Result::Continue;

        SymbolStruct* instance = nullptr;
        SWC_RESULT(SemaGeneric::instantiateStructFromContext(sema, *genericRoot, instance));
        if (!instance)
            return Result::Continue;

        const TypeRef specializedTypeRef = SemaHelpers::ensureStructTypeRef(sema, *instance);
        if (specializedTypeRef.isValid())
        {
            ioTypeRef = specializedTypeRef;
            sema.setSymbol(nodeRef, instance);
        }
        return Result::Continue;
    }

    const SymbolMap* namespacePathOwner(const SymbolMap* current)
    {
        const SymbolMap* next = current->ownerSymMap();
        if (!next && current->isImpl())
        {
            const auto& impl = current->cast<SymbolImpl>();
            if (impl.isForStruct())
                next = impl.symStruct()->ownerSymMap();
            else if (impl.isForEnum())
                next = impl.symEnum()->ownerSymMap();
        }

        return next;
    }

    void collectSymbolMapNamespacePath(const SymbolMap* symMap, SmallVector<IdentifierRef>& outPath)
    {
        SmallVector<IdentifierRef> reversedPath;
        for (const SymbolMap* current = symMap; current;)
        {
            const SymbolMap* owner = current->ownerSymMap();
            if (current->isNamespace() && (!owner || !owner->isModule()))
                reversedPath.push_back(current->idRef());

            current = namespacePathOwner(current);
        }

        outPath.clear();
        outPath.reserve(reversedPath.size());
        for (auto& it : std::views::reverse(reversedPath))
            outPath.push_back(it);
    }

    SymbolAccess accessForSymbolMap(const SymbolMap* symMap)
    {
        for (const SymbolMap* current = symMap; current; current = namespacePathOwner(current))
        {
            if (current->isModule())
                return SymbolAccess::ModulePrivate;
        }

        return SymbolAccess::FilePrivate;
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
        const SymbolAccess access                  = startSymMap ? accessForSymbolMap(startSymMap) : sema.frame().currentAccess();
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

        const SemaNodeView typedView = sema.viewNodeTypeConstantSymbol(nodeRef);
        if (typedView.typeRef().isValid() && SemaHelpers::isTypeLikeTypeRef(sema.ctx(), typedView.typeRef()))
        {
            TypeRef representedTypeRef = SemaHelpers::resolveRepresentedTypeRef(sema, typedView);
            SWC_RESULT(specializeExplicitGenericTypeArgFromContext(sema, nodeRef, representedTypeRef));
            if (representedTypeRef.isValid())
            {
                outArg.typeRef = representedTypeRef;
                outArg.present = true;
                return Result::Continue;
            }
        }

        const SemaNodeView typeView = sema.viewNodeType(nodeRef);
        if (typeView.typeRef().isValid())
        {
            TypeRef typeRef = typeView.typeRef();
            SWC_RESULT(specializeExplicitGenericTypeArgFromContext(sema, nodeRef, typeRef));
            const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
            if (!sema.isValue(nodeRef) || typeInfo.isAggregate())
            {
                // Explicit type arguments only need the resolved type. Avoid forcing symbol payload
                // queries on complex type syntax such as quoted generic specializations or
                // anonymous aggregate type expressions.
                outArg.typeRef = typeRef;
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
            SWC_RESULT(specializeExplicitGenericTypeArgFromContext(sema, nodeRef, typeRef));

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
