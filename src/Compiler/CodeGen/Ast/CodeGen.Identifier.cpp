#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void resolveIdentifierVariablePayload(CodeGenNodePayload& outPayload, CodeGen& codeGen, const SymbolVariable& symVar)
    {
        const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar);
        if (symbolPayload)
        {
            outPayload = *symbolPayload;
            return;
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const SymbolFunction& symbolFunc = codeGen.function();
            CodeGenNodePayload    paramPayload;
            CodeGenHelpers::materializeFunctionParameterPayload(paramPayload, codeGen, symbolFunc, symVar);
            codeGen.setVariablePayload(symVar, paramPayload);
            outPayload = *codeGen.variablePayload(symVar);
            return;
        }

        SWC_UNREACHABLE();
    }

    Result codeGenIdentifierVariable(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        CodeGenNodePayload symbolPayload;
        resolveIdentifierVariablePayload(symbolPayload, codeGen, symVar);

        CodeGenNodePayload& payload = codeGen.setPayload(codeGen.curNodeRef(), symVar.typeRef());
        payload.reg                 = symbolPayload.reg;
        payload.storageKind         = symbolPayload.storageKind;
        return Result::Continue;
    }

    Result codeGenIdentifierFromSymbol(CodeGen& codeGen, const Symbol& symbol)
    {
        switch (symbol.kind())
        {
            case SymbolKind::Variable:
                return codeGenIdentifierVariable(codeGen, symbol.cast<SymbolVariable>());

            case SymbolKind::Function:
                return Result::Continue;

            default:
                SWC_UNREACHABLE();
        }
    }

    void bindSingleVariableFromInitializer(CodeGen& codeGen, const SymbolVariable& symVar, AstNodeRef initRef)
    {
        if (initRef.isInvalid())
            return;

        const CodeGenNodePayload* initPayload = codeGen.payload(initRef);
        if (!initPayload)
            return;

        CodeGenNodePayload symbolPayload = *initPayload;
        symbolPayload.typeRef            = symVar.typeRef();
        codeGen.setVariablePayload(symVar, symbolPayload);
    }
}

Result AstIdentifier::codeGenPostNode(CodeGen& codeGen)
{
    const SemaNodeView nodeView = codeGen.curNodeView();
    SWC_ASSERT(nodeView.sym);
    return codeGenIdentifierFromSymbol(codeGen, *nodeView.sym);
}

Result AstSingleVarDecl::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView nodeView = codeGen.curNodeView();
    SWC_ASSERT(nodeView.sym);
    const SymbolVariable& symVar = nodeView.sym->cast<SymbolVariable>();

    if (hasFlag(AstVarDeclFlagsE::Parameter))
    {
        const SymbolFunction& symbolFunc = codeGen.function();
        CodeGenNodePayload    symbolPayload;
        CodeGenHelpers::materializeFunctionParameterPayload(symbolPayload, codeGen, symbolFunc, symVar);
        codeGen.setVariablePayload(symVar, symbolPayload);
        return Result::Continue;
    }

    bindSingleVariableFromInitializer(codeGen, symVar, nodeInitRef);
    return Result::Continue;
}

Result AstMultiVarDecl::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView nodeView = codeGen.curNodeView();
    SWC_ASSERT(!nodeView.symList.empty());

    if (hasFlag(AstVarDeclFlagsE::Parameter))
    {
        const SymbolFunction& symbolFunc = codeGen.function();

        for (Symbol* sym : nodeView.symList)
        {
            const SymbolVariable& symVar = sym->cast<SymbolVariable>();

            CodeGenNodePayload symbolPayload;
            CodeGenHelpers::materializeFunctionParameterPayload(symbolPayload, codeGen, symbolFunc, symVar);
            codeGen.setVariablePayload(symVar, symbolPayload);
        }

        return Result::Continue;
    }

    if (nodeView.symList.size() == 1)
    {
        const SymbolVariable& symVar = nodeView.symList.front()->cast<SymbolVariable>();
        bindSingleVariableFromInitializer(codeGen, symVar, nodeInitRef);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
