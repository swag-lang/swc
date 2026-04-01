#pragma once
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGeneric
{
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

        static InstanceSymbol* findInstance(const SymbolFunction& root, std::span<const GenericInstanceKey> keys)
        {
            return root.findGenericInstance(keys);
        }

        static InstanceSymbol* addInstance(SymbolFunction& root, std::span<const GenericInstanceKey> keys, InstanceSymbol* instance)
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

        static InstanceSymbol* findInstance(const SymbolStruct& root, std::span<const GenericInstanceKey> keys)
        {
            return root.findGenericInstance(keys);
        }

        static InstanceSymbol* addInstance(SymbolStruct& root, std::span<const GenericInstanceKey> keys, InstanceSymbol* instance)
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
}

SWC_END_NAMESPACE();
