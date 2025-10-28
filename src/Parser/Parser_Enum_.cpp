#include "pch.h"

#include "Parser/AstNodes.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseEnum()
{
    auto [nodeRef, nodePtr] = ast_->makeNodePtr<AstNodeEnumDecl>(AstNodeId::File, consume());

    if (isNot(TokenId::Identifier))
    {
        expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenAfter);
        skipUntil({TokenId::SymLeftCurly, TokenId::SymColon}, SkipUntilFlags::DoNotConsume);
    }
    else
        nodePtr->name = consume();

    SmallVector<AstNodeRef> stmts;

    return nodeRef;
}

SWC_END_NAMESPACE();
