#pragma once
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGenericStoredType
{
    inline bool resolve(Sema& sema, AstNodeRef nodeRef, TypeRef& outTypeRef)
    {
        outTypeRef = TypeRef::invalid();
        if (nodeRef.isInvalid())
            return false;

        const SemaNodeView storedView = sema.viewStored(nodeRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
        outTypeRef                    = storedView.typeRef();
        if (!outTypeRef.isValid() && storedView.hasSymbol() && storedView.sym() && storedView.sym()->isType())
            outTypeRef = storedView.sym()->typeRef();

        if (!outTypeRef.isValid())
        {
            const AstNode& typeNode = sema.node(nodeRef);
            if (const auto* namedType = typeNode.safeCast<AstNamedType>())
            {
                const SemaNodeView identView = sema.viewStored(namedType->nodeIdentRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
                outTypeRef                   = identView.typeRef();
                if (!outTypeRef.isValid() && identView.hasSymbol() && identView.sym() && identView.sym()->isType())
                    outTypeRef = identView.sym()->typeRef();
            }
        }

        return outTypeRef.isValid();
    }
}

SWC_END_NAMESPACE();
