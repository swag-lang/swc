#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseBlock(AstNodeId blockNodeId, TokenId tokenStartId)
{
    const Token&   openTok    = tok();
    const TokenRef openTokRef = ref();
    const auto     tokenEndId = Token::toRelated(tokenStartId);

    if (tokenStartId != TokenId::Invalid)
    {
        const auto tokenOpenRef = expectAndConsume(tokenStartId, DiagnosticId::ParserExpectedTokenAfter);
        if (isInvalid(tokenOpenRef))
            return INVALID_REF;
    }

    SmallVector<AstNodeRef> childrenRefs;
    while (!atEnd() && isNot(tokenEndId))
    {
        EnsureConsume ec(*this);
        AstNodeRef    childrenRef = INVALID_REF;

        // Compiler instructions
        if (blockNodeId == AstNodeId::File ||
            blockNodeId == AstNodeId::TopLevelBlock ||
            blockNodeId == AstNodeId::ImplBlock ||
            blockNodeId == AstNodeId::EnumBlock)
        {
            switch (id())
            {
            case TokenId::CompilerAssert:
                childrenRef = parseCallArg1(AstNodeId::CompilerAssert);
                expectEndStatement();
                break;
            case TokenId::CompilerError:
                childrenRef = parseCallArg1(AstNodeId::CompilerError);
                expectEndStatement();
                break;
            case TokenId::CompilerWarning:
                childrenRef = parseCallArg1(AstNodeId::CompilerWarning);
                expectEndStatement();
                break;
            case TokenId::CompilerPrint:
                childrenRef = parseCallArg1(AstNodeId::CompilerPrint);
                expectEndStatement();
                break;
            default:
                break;
            }
        }

        if (isValid(childrenRef))
            childrenRefs.push_back(childrenRef);

        // One block element
        switch (blockNodeId)
        {
        case AstNodeId::File:
        case AstNodeId::TopLevelBlock:
        case AstNodeId::ImplBlock:
            childrenRef = parseTopLevelStmt();
            break;
        case AstNodeId::FuncBody:
        case AstNodeId::EmbeddedBlock:
            childrenRef = parseEmbeddedStmt();
            break;
        case AstNodeId::EnumBlock:
            childrenRef = parseEnumValue();
            break;
        case AstNodeId::ArrayLiteral:
            childrenRef = parseExpression();
            break;
        case AstNodeId::UnnamedArgumentBlock:
            childrenRef = parseExpression();
            break;
        case AstNodeId::NamedArgumentBlock:
            childrenRef = parseNamedArgument();
            break;

        default:
            std::unreachable();
        }

        // Separator
        switch (blockNodeId)
        {
        case AstNodeId::EnumBlock:
            if (!consumeIfAny(TokenId::SymComma) && !is(tokenEndId) && !tok().startsLine())
            {
                auto diag = reportError(DiagnosticId::ParserExpectedTokenAfter, ref());
                setReportExpected(diag, TokenId::SymComma);
                diag.report(*ctx_);
                skipTo({TokenId::SymComma, tokenEndId});
            }
            break;

        case AstNodeId::ArrayLiteral:
        case AstNodeId::UnnamedArgumentBlock:
        case AstNodeId::NamedArgumentBlock:
            if (!consumeIfAny(TokenId::SymComma) && !is(tokenEndId))
            {
                auto diag = reportError(DiagnosticId::ParserExpectedTokenAfter, ref());
                setReportExpected(diag, TokenId::SymComma);
                diag.report(*ctx_);
                skipTo({TokenId::SymComma, tokenEndId});
            }
            break;

        default:
            break;
        }

        // Be sure instruction has not failed
        if (isValid(childrenRef))
            childrenRefs.push_back(childrenRef);
    }

    // Consume end token if necessary
    if (!consumeIf(tokenEndId) && tokenEndId != TokenId::Invalid)
    {
        auto diag = reportError(DiagnosticId::ParserExpectedClosing, openTokRef);
        setReportExpected(diag, Token::toRelated(openTok.id));
        diag.report(*ctx_);
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeBlock>(blockNodeId);
    nodePtr->spanChildren   = ast_->store_.push_span(std::span(childrenRefs.data(), childrenRefs.size()));
    return nodeRef;
}

AstNodeRef Parser::parseFile()
{
    return parseBlock(AstNodeId::File, TokenId::Invalid);
}

AstNodeRef Parser::parseTopLevelStmt()
{
    switch (id())
    {
    case TokenId::SymLeftCurly:
        return parseBlock(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    case TokenId::SymRightCurly:
        raiseError(DiagnosticId::ParserUnexpectedToken, ref());
        return INVALID_REF;

    case TokenId::SymSemiColon:
        consume();
        return INVALID_REF;

    case TokenId::KwdEnum:
        return parseEnum();

    case TokenId::KwdImpl:
        return parseImpl();

    case TokenId::CompilerFuncTest:
    case TokenId::CompilerFuncMain:
    case TokenId::CompilerFuncPreMain:
    case TokenId::CompilerFuncInit:
    case TokenId::CompilerFuncDrop:
    case TokenId::CompilerAst:
        return parseCompilerFunc();

    case TokenId::KwdNamespace:
        return parseNamespace();

    default:
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlags::EolBefore);
        return INVALID_REF;
    }
}

AstNodeRef Parser::parseEmbeddedStmt()
{
    switch (id())
    {
    case TokenId::SymLeftCurly:
        return parseBlock(AstNodeId::EmbeddedBlock, TokenId::SymLeftCurly);
    case TokenId::SymRightCurly:
        raiseError(DiagnosticId::ParserUnexpectedToken, ref());
        return INVALID_REF;

    case TokenId::SymSemiColon:
        consume();
        return INVALID_REF;

    default:
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlags::EolBefore);
        return INVALID_REF;
    }
}

AstNodeRef Parser::parseNamespace()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Namespace>();
    nodePtr->nodeName       = parseScopedIdentifier();
    if (isInvalid(nodePtr->nodeName))
        skipTo({TokenId::SymLeftCurly});
    nodePtr->nodeBody = parseBlock(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
