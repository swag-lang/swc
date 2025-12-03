#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"
#include "Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstVarDecl::semaPostNode(Sema& sema) const
{
    if (hasParserFlag(Const))
    {
        if (nodeInitRef.isInvalid())
        {
            sema.raiseError(DiagnosticId::sema_err_const_missing_init, srcViewRef(), tokNameRef);
            return AstVisitStepResult::Stop;
        }

        if (!sema.hasConstant(nodeInitRef))
        {
            sema.raiseExprNotConst(nodeInitRef);
            return AstVisitStepResult::Stop;
        }
    }
    else
    {
        sema.raiseInternalError(*this);
        return AstVisitStepResult::Stop;
    }

    // SemaNodeView type(sema, nodeTypeRef);
    // SemaNodeView init(sema, nodeInitRef);

    CompilerInstance&      compiler = sema.compiler();
    const Token&           tok      = sema.token(srcViewRef(), tokNameRef);
    const SourceView&      srcView  = compiler.srcView(srcViewRef());
    const std::string_view name     = tok.string(srcView);
    const uint32_t         crc      = tok.crc(srcView);
    const IdentifierRef    idRef    = compiler.idMgr().addIdentifier(name, crc);

    const auto cst = new SymbolConstant(sema.ctx(), idRef, sema.constantRefOf(nodeInitRef));
    sema.setSymbol(sema.curNodeRef(), cst);

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
