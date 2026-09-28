#pragma once
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

namespace SemaVarDeclHelpers
{
    inline AstNodeRef singleDeclarationRef(Sema& sema, AstNodeRef varDeclRef)
    {
        const AstNode& varNode = sema.node(varDeclRef);
        if (varNode.is(AstNodeId::VarDeclList))
        {
            const auto&             list = varNode.cast<AstVarDeclList>();
            SmallVector<AstNodeRef> decls;
            sema.ast().appendNodes(decls, list.spanChildrenRef);
            if (decls.size() != 1)
                return AstNodeRef::invalid();
            return decls.front();
        }

        return varDeclRef;
    }
}

SWC_END_NAMESPACE();
