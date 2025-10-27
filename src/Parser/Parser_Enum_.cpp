#include "pch.h"

#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseEnum()
{
    const auto myTokenRef = tokenRef();
    const auto myToken    = curToken_;

    SmallVector<AstNodeRef> stmts;
    consume();

    return ast_->makeBlock(AstNodeId::Enum, myTokenRef, stmts);
}

SWC_END_NAMESPACE();
