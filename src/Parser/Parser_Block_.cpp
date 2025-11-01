#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseBlock(AstNodeId blockId, TokenId tokenStart)
{
    const Token& openToken = tok();

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeBlock>(blockId);
    if (tokenStart != TokenId::Invalid)
    {
        consume();
    }

    const auto tokenEnd = Token::toRelated(openToken.id);

    SmallVector<AstNodeRef> stmts;
    while (!atEnd() && isNot(tokenEnd))
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
    if (tokenEnd != TokenId::Invalid)
    {
        if (is(tokenEnd))
            skip();
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

AstNodeRef Parser::parseImpl()
{
    if (nextIs(TokenId::KwdEnum))
        return parseEnumImpl();
    return INVALID_REF;
}

AstNodeRef Parser::parseTopLevelInstruction()
{
    switch (id())
    {
    case TokenId::SymLeftCurly:
        return parseBlock(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    case TokenId::SymRightCurly:
        (void) reportError(DiagnosticId::ParserUnexpectedToken, tok());
        return INVALID_REF;

    case TokenId::SymSemiColon:
        skip();
        return INVALID_REF;

    case TokenId::KwdEnum:
        return parseEnum();

    case TokenId::KwdImpl:
        return parseImpl();

    default:
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlags::EolBefore);
        return INVALID_REF;
    }
}

SWC_END_NAMESPACE()
