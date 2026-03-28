#pragma once
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGenericInternal
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

    template<typename T>
    SymbolFlags clonedGenericSymbolFlags(const T& root)
    {
        SymbolFlags flags = SymbolFlagsE::Zero;
        if (root.isPublic())
            flags.add(SymbolFlagsE::Public);
        return flags;
    }

    template<typename T>
    struct GenericRootTraits;

    template<>
    struct GenericRootTraits<SymbolFunction>
    {
        using DeclType       = AstFunctionDecl;
        using GenericArgKey  = SymbolFunction::GenericArgKey;
        using InstanceSymbol = SymbolFunction;

        static const DeclType* decl(const SymbolFunction& root)
        {
            return root.decl() ? root.decl()->safeCast<DeclType>() : nullptr;
        }

        static bool hasGenericParams(const SymbolFunction& root)
        {
            const auto* funcDecl = decl(root);
            return !root.isGenericInstance() && funcDecl && funcDecl->spanGenericParamsRef.isValid();
        }

        static Result runNode(Sema& sema, const SymbolFunction& root, AstNodeRef nodeRef)
        {
            Sema child(sema.ctx(), sema, nodeRef);
            child.prepareGenericInstantiationContext(const_cast<SymbolMap*>(root.ownerSymMap()), root.genericDeclImpl(), root.genericDeclInterface(), root.attributes());
            return child.execResult();
        }

        static InstanceSymbol* findInstance(const SymbolFunction& root, std::span<const GenericArgKey> keys)
        {
            return root.findGenericInstance(keys);
        }

        static InstanceSymbol* addInstance(SymbolFunction& root, std::span<const GenericArgKey> keys, InstanceSymbol* instance)
        {
            return root.addGenericInstance(keys, instance);
        }

        static InstanceSymbol* createInstance(Sema& sema, SymbolFunction& root, AstNodeRef cloneRef)
        {
            auto& cloneDecl                = sema.node(cloneRef).cast<DeclType>();
            cloneDecl.spanGenericParamsRef = SpanRef::invalid();

            auto* instance         = Symbol::make<InstanceSymbol>(sema.ctx(), &cloneDecl, cloneDecl.tokNameRef, root.idRef(), clonedGenericSymbolFlags(root));
            instance->extraFlags() = root.extraFlags();
            instance->setAttributes(root.attributes());
            instance->setRtAttributeFlags(root.rtAttributeFlags());
            instance->setSpecOpKind(root.specOpKind());
            instance->setCallConvKind(root.callConvKind());
            instance->setDeclNodeRef(cloneRef);
            instance->setOwnerSymMap(root.ownerSymMap());
            instance->setGenericInstance(&root);
            return instance;
        }
    };

    template<>
    struct GenericRootTraits<SymbolStruct>
    {
        using DeclType       = AstStructDecl;
        using GenericArgKey  = SymbolStruct::GenericArgKey;
        using InstanceSymbol = SymbolStruct;

        static const DeclType* decl(const SymbolStruct& root)
        {
            return root.decl() ? root.decl()->safeCast<DeclType>() : nullptr;
        }

        static bool hasGenericParams(const SymbolStruct& root)
        {
            const auto* structDecl = decl(root);
            return !root.isGenericInstance() && structDecl && structDecl->spanGenericParamsRef.isValid();
        }

        static Result runNode(Sema& sema, const SymbolStruct& root, AstNodeRef nodeRef)
        {
            Sema child(sema.ctx(), sema, nodeRef);
            child.prepareGenericInstantiationContext(const_cast<SymbolMap*>(root.ownerSymMap()), nullptr, nullptr, root.attributes());
            return child.execResult();
        }

        static InstanceSymbol* findInstance(const SymbolStruct& root, std::span<const GenericArgKey> keys)
        {
            return root.findGenericInstance(keys);
        }

        static InstanceSymbol* addInstance(SymbolStruct& root, std::span<const GenericArgKey> keys, InstanceSymbol* instance)
        {
            return root.addGenericInstance(keys, instance);
        }

        static InstanceSymbol* createInstance(Sema& sema, SymbolStruct& root, AstNodeRef cloneRef)
        {
            auto& cloneDecl                = sema.node(cloneRef).cast<DeclType>();
            cloneDecl.spanGenericParamsRef = SpanRef::invalid();
            cloneDecl.spanWhereRef         = SpanRef::invalid();

            auto* instance         = Symbol::make<InstanceSymbol>(sema.ctx(), &cloneDecl, cloneDecl.tokNameRef, root.idRef(), clonedGenericSymbolFlags(root));
            instance->extraFlags() = root.extraFlags();
            instance->setAttributes(root.attributes());
            instance->setOwnerSymMap(root.ownerSymMap());
            instance->setDeclNodeRef(cloneRef);
            instance->setGenericInstance(&root);
            return instance;
        }
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
}

namespace SemaGeneric
{
    Result instantiateFunctionExplicit(Sema& sema, SymbolFunction& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolFunction*& outInstance);
    Result instantiateFunctionFromCall(Sema& sema, SymbolFunction& genericRoot, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SymbolFunction*& outInstance);
    Result instantiateStructExplicit(Sema& sema, SymbolStruct& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolStruct*& outInstance);
}

SWC_END_NAMESPACE();
