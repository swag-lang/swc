#include "pch.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCompilerAssert()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerAssert>();
    nodePtr->tokRef         = consume(TokenId::CompilerAssert);

    const auto openRef = ref();
    expectAndSkip(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenAfter);
    nodePtr->nodeExpr = parseExpression();
    if (isInvalid(nodePtr->nodeExpr))
        skipTo({TokenId::SymRightParen}, SkipUntilFlags::EolBefore);
    expectAndSkipClosing(TokenId::SymLeftParen, openRef);
    expectEndStatement();

    return nodeRef;
}

SWC_END_NAMESPACE()
