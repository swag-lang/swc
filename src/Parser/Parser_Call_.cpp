#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCallerSingleArg(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCallerSingleArg>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndSkip(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenAfter);
    nodePtr->nodeExpr = parseExpression();
    if (isInvalid(nodePtr->nodeExpr))
        skipTo({TokenId::SymRightParen}, SkipUntilFlags::EolBefore);
    expectAndSkipClosing(TokenId::SymLeftParen, openRef);
    expectEndStatement();

    return INVALID_REF;
}

SWC_END_NAMESPACE()
