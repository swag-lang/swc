#include "pch.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCompilerAssert()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerAssert>();
    consume(TokenId::CompilerAssert);

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenAfter);
    nodePtr->nodeExpr = parseExpression();
    expectAndConsumeClosing(TokenId::SymLeftParen, openRef);
    expectEndOfLine();

    return nodeRef;
}

SWC_END_NAMESPACE()
