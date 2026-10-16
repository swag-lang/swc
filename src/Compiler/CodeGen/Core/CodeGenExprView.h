#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenExprView
{
    // The type 'payload' carries, or the sema type of 'nodeRef' when it carries none.
    inline TypeRef payloadTypeRef(CodeGen& codeGen, const CodeGenNodePayload& payload, AstNodeRef nodeRef)
    {
        return payload.typeRef.isValid() ? payload.typeRef : codeGen.viewType(nodeRef).typeRef();
    }

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
