#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenExprView
{
    inline SemaNodeView storedOrType(CodeGen& codeGen, AstNodeRef exprRef)
    {
        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Type);
        if (storedView.type() != nullptr)
            return storedView;
        return codeGen.viewType(exprRef);
    }
}

SWC_END_NAMESPACE();
