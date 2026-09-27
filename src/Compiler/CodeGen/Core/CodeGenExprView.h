#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

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

    inline SymbolFunction* singleFunction(const SemaNodeView& view)
    {
        Symbol* symbol = view.singleSymbol();
        if (!symbol || !symbol->isFunction())
            return nullptr;
        return &symbol->cast<SymbolFunction>();
    }
}

SWC_END_NAMESPACE();
