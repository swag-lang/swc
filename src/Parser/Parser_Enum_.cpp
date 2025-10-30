#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseEnumValue()
{
    EnsureConsume ec(*this);

    auto [nodeRef, nodePtr] = ast_->makeNodePtr<AstNodeEnumDecl>(AstNodeId::EnumValue, ref());

    // Name
    nodePtr->name = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedToken);
    if (isInvalid(nodePtr->name))
        skipTo({TokenId::SymRightCurly, TokenId::SymComma, TokenId::SymSemiColon}, SkipUntilFlags::StopAfterEol);

    // Value

    return nodeRef;
}

AstNodeRef Parser::parseEnum()
{
    EnsureConsume ec(*this);

    auto [nodeRef, nodePtr] = ast_->makeNodePtr<AstNodeEnumDecl>(AstNodeId::EnumDecl, consume());

    // Name
    nodePtr->name = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFamAfter);
    if (isInvalid(nodePtr->name))
        skipTo({TokenId::SymLeftCurly, TokenId::SymColon, TokenId::SymSemiColon});

    // Type
    if (is(TokenId::SymColon))
    {
        consumeTrivia();
        nodePtr->type = parseType();
        if (isInvalid(nodePtr->type))
            skipTo({TokenId::SymLeftCurly, TokenId::SymRightCurly, TokenId::SymSemiColon});
    }

    // Content
    const auto leftCurly = expect(TokenId::SymLeftCurly, DiagnosticId::ParserExpectedTokenAfter);
    if (isInvalid(leftCurly))
    {
        skipTo({TokenId::SymLeftCurly, TokenId::SymRightCurly, TokenId::SymSemiColon});
        if (isNot(TokenId::SymLeftCurly))
        {
            nodePtr->body = INVALID_REF;
            if (is(TokenId::SymRightCurly) || is(TokenId::SymSemiColon))
                consume();
            return nodeRef;
        }
    }

    nodePtr->body = parseBlock(AstNodeId::EnumBlock, TokenId::SymRightCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
