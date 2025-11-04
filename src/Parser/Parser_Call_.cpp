#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCallArg1(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCall1>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenAfter);
    nodePtr->nodeParam1 = parseExpression();
    if (isInvalid(nodePtr->nodeParam1))
        skipTo({TokenId::SymRightParen});
    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCallArg2(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCall2>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenAfter);

    nodePtr->nodeParam1 = parseExpression();
    if (isInvalid(nodePtr->nodeParam1))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});
    expectAndConsume(TokenId::SymComma, DiagnosticId::ParserExpectedToken);

    nodePtr->nodeParam2 = parseExpression();
    if (isInvalid(nodePtr->nodeParam2))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseCallArg3(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCall3>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenAfter);

    nodePtr->nodeParam1 = parseExpression();
    if (isInvalid(nodePtr->nodeParam1))
        skipTo({TokenId::SymRightParen});
    expectAndConsume(TokenId::SymComma, DiagnosticId::ParserExpectedToken);

    nodePtr->nodeParam2 = parseExpression();
    if (isInvalid(nodePtr->nodeParam2))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});
    expectAndConsume(TokenId::SymComma, DiagnosticId::ParserExpectedToken);

    nodePtr->nodeParam3 = parseExpression();
    if (isInvalid(nodePtr->nodeParam2))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseAttribute()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Attribute>();
    nodePtr->nodeIdentifier = parseScopedIdentifier();
    if (is(TokenId::SymLeftParen))
        nodePtr->nodeArgs = parseBlock(AstNodeId::NamedArgumentBlock, TokenId::SymLeftParen);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerAttribute(AstNodeId blockNodeId)
{
    const auto openTokRef = ref();
    const auto openTok    = tok();

    // Create a ScopeAccess node with left and right
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AttributeBlock>();
    consume(TokenId::SymAttrStart);

    if (consumeIf(TokenId::SymRightBracket))
    {
        nodePtr->spanChildren = INVALID_REF;
        const auto diag       = reportError(DiagnosticId::ParserEmptyAttribute, ref());
        diag.report(*ctx_);
    }
    else
    {
        // Parse the first identifier
        SmallVector<AstNodeRef> childrenRefs;
        while (!atEnd() && !is(TokenId::SymRightBracket))
        {
            const auto childrenRef = parseAttribute();
            if (isValid(childrenRef))
                childrenRefs.push_back(childrenRef);

            if (consumeIf(TokenId::SymComma))
                continue;
            if (is(TokenId::SymRightBracket))
                break;

            auto diag = reportError(DiagnosticId::ParserExpectedTokenAfter, ref());
            setReportExpected(diag, TokenId::SymComma);
            diag.report(*ctx_);
            skipTo({TokenId::SymComma, TokenId::SymRightBracket});
        }

        // Consume end token
        if (!consumeIf(TokenId::SymRightBracket))
        {
            auto diag = reportError(DiagnosticId::ParserExpectedClosing, openTokRef);
            setReportExpected(diag, Token::toRelated(openTok.id));
            diag.report(*ctx_);
        }

        nodePtr->spanChildren = ast_->store_.push_span(std::span(childrenRefs.data(), childrenRefs.size()));
    }

    if (is(TokenId::SymLeftCurly))
        nodePtr->nodeBody = parseBlock(blockNodeId, TokenId::SymLeftCurly);
    else
        nodePtr->nodeBody = parseBlockStmt(blockNodeId);
    return nodeRef;
}

SWC_END_NAMESPACE()
