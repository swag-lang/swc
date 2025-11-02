#include "pch.h"
#include "Parser/AstNode.h"
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

    SmallVector<AstNodeRef> childrenRefs;
    while (!atEnd() && isNot(tokenEndId))
    {
        EnsureConsume ec(*this);
        AstNodeRef    childrenRef = INVALID_REF;

        switch (id())
        {
        case TokenId::CompilerAssert:
            childrenRef = parseCallerSingleArg(AstNodeId::CompilerAssert);
            break;
        case TokenId::CompilerError:
            childrenRef = parseCallerSingleArg(AstNodeId::CompilerError);
            break;
        case TokenId::CompilerWarning:
            childrenRef = parseCallerSingleArg(AstNodeId::CompilerWarning);
            break;
        case TokenId::CompilerPrint:
            childrenRef = parseCallerSingleArg(AstNodeId::CompilerPrint);
            break;
        default:
            break;
        }

        if (isValid(childrenRef))
            childrenRefs.push_back(childrenRef);

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
        if (isValid(childrenRef))
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

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeBlock>(blockNodeId);
    nodePtr->nodeChildren   = ast_->store_.push_span(std::span(childrenRefs.data(), childrenRefs.size()));
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
