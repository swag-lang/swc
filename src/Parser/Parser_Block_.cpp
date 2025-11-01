#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseBlock(AstNodeId blockNodeId, TokenId tokenStartId)
{
    const Token& openTok    = tok();
    const auto   tokenEndId = Token::toRelated(tokenStartId);

    if (tokenStartId != TokenId::Invalid)
    {
        const auto tokenOpenRef = expectAndSkip(tokenStartId, DiagnosticId::ParserExpectedTokenAfter);
        if (isInvalid(tokenOpenRef))
            return INVALID_REF;
    }

    AstNodeRef    nodeRef;
    AstNodeBlock* nodePtr;
    switch (blockNodeId)
    {
    case AstNodeId::File:
    {
        const auto pair = ast_->makeNode<AstNodeFile>();
        nodeRef         = pair.first;
        nodePtr         = static_cast<AstNodeBlock*>(pair.second);
        break;
    }
    case AstNodeId::TopLevelBlock:
    {
        const auto pair = ast_->makeNode<AstNodeTopLevelBlock>();
        nodeRef         = pair.first;
        nodePtr         = static_cast<AstNodeBlock*>(pair.second);
        break;
    }
    case AstNodeId::EnumBlock:
    {
        const auto pair = ast_->makeNode<AstNodeEnumBlock>();
        nodeRef         = pair.first;
        nodePtr         = static_cast<AstNodeBlock*>(pair.second);
        break;
    }
    default:
        std::unreachable();
    }

    SmallVector<AstNodeRef> childrenRefs;
    while (!atEnd() && isNot(tokenEndId))
    {
        EnsureConsume ec(*this);

        AstNodeRef childrenRef;
        switch (blockNodeId)
        {
        case AstNodeId::File:
        case AstNodeId::TopLevelBlock:
            childrenRef = parseTopLevelInstruction();
            break;

        case AstNodeId::EnumBlock:
            childrenRef = parseEnumValue();
            break;

        default:
            std::unreachable();
        }

        // Be sure instruction has not failed
        if (!isInvalid(childrenRef))
            childrenRefs.push_back(childrenRef);
    }

    // Consume end token if necessary
    if (is(tokenEndId))
        skip();
    else if (tokenEndId != TokenId::Invalid)
    {
        auto diag = reportError(DiagnosticId::ParserExpectedClosing, openTok);
        diag.addArgument(Diagnostic::ARG_EXPECT, Token::toName(Token::toRelated(openTok.id)));
    }

    nodePtr->nodeChildren = ast_->store_.push_span(std::span(childrenRefs.data(), childrenRefs.size()));
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
