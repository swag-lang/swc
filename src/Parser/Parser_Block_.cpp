#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseBlock(AstNodeId blockId, TokenId blockTokenEnd)
{
    const Token& openToken = tok();

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeBlock>(blockId);
    if (blockTokenEnd != TokenId::Invalid)
        consume();

    SmallVector<AstNodeRef> stmts;
    while (!atEnd() && isNot(blockTokenEnd))
    {
        EnsureConsume ec(*this);

        AstNodeRef stmt;
        switch (blockId)
        {
        case AstNodeId::File:
        case AstNodeId::TopLevelBlock:
            stmt = parseTopLevelInstruction();
            break;

        case AstNodeId::EnumBlock:
            stmt = parseEnumValue();
            break;

        default:
            std::unreachable();
        }

        // Be sure instruction has not failed
        if (!isInvalid(stmt))
            stmts.push_back(stmt);
    }

    // Consume end token if necessary
    if (blockTokenEnd != TokenId::Invalid)
    {
        if (is(blockTokenEnd))
            consumeTrivia();
        else
        {
            auto diag = reportError(DiagnosticId::ParserExpectedClosing, openToken);
            diag.addArgument(Diagnostic::ARG_EXPECT, Token::toName(Token::toRelated(openToken.id)));
        }
    }

    nodePtr->nodeChildren = ast_->store_.push_span(std::span(stmts.data(), stmts.size()));
    return nodeRef;
}

AstNodeRef Parser::parseFile()
{
    return parseBlock(AstNodeId::File, TokenId::Invalid);
}

AstNodeRef Parser::parseTopLevelInstruction()
{
    switch (id())
    {
    case TokenId::SymLeftCurly:
        return parseBlock(AstNodeId::TopLevelBlock, TokenId::SymRightCurly);
    case TokenId::SymRightCurly:
        (void) reportError(DiagnosticId::ParserUnexpectedToken, tok());
        return INVALID_REF;

    case TokenId::SymSemiColon:
        consumeTrivia();
        return INVALID_REF;

    case TokenId::KwdEnum:
        return parseEnum();

    default:
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlags::EolBefore);
        return INVALID_REF;
    }
}

SWC_END_NAMESPACE()
