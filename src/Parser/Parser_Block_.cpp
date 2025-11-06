#include "pch.h"
#include "Core/SmallVector.h"
#include "Core/Types.h"
#include "Lexer/SourceFile.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseBlockStmt(AstNodeId blockNodeId)
{
    switch (blockNodeId)
    {
    case AstNodeId::File:
    case AstNodeId::TopLevelBlock:
    case AstNodeId::ImplBlock:
        return parseTopLevelStmt();
    case AstNodeId::FuncBody:
    case AstNodeId::EmbeddedBlock:
        return parseEmbeddedStmt();
    case AstNodeId::EnumBlock:
        return parseEnumValue();
    case AstNodeId::AttributeBlock:
        return parseAttribute();
    case AstNodeId::ArrayLiteral:
        return parseExpression();
    case AstNodeId::UnnamedArgumentBlock:
        return parseExpression();
    case AstNodeId::NamedArgumentBlock:
        return parseNamedArgument();
    case AstNodeId::UsingBlock:
        return parseScopedIdentifier();

    default:
        std::unreachable();
    }
}

AstNodeRef Parser::parseBlockCompilerDirective(AstNodeId blockNodeId)
{
    auto childrenRef = INVALID_REF;

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
        case TokenId::CompilerIf:
            childrenRef = parseCompilerIf(blockNodeId);
            break;
        default:
            break;
        }
    }

    return childrenRef;
}

Result Parser::parseBlockSeparator(AstNodeId blockNodeId, TokenId tokenEndId)
{
    SmallVector skipTokens = {TokenId::SymComma, tokenEndId};
    if (depthParen_)
        skipTokens.push_back(TokenId::SymRightParen);
    if (depthBracket_)
        skipTokens.push_back(TokenId::SymRightBracket);
    if (depthCurly_)
        skipTokens.push_back(TokenId::SymRightCurly);

    switch (blockNodeId)
    {
    case AstNodeId::EnumBlock:
        if (!consumeIf(TokenId::SymComma) && !is(tokenEndId) && !tok().startsLine())
        {
            if (is(TokenId::Identifier))
                raiseError(DiagnosticId::parser_err_missing_enum_sep, ref());
            else
                raiseExpected(DiagnosticId::parser_err_expected_token_before, ref(), TokenId::SymComma);
            skipTo(skipTokens);
            return Result::Error;
        }
        break;

    case AstNodeId::AttributeBlock:
        if (!consumeIf(TokenId::SymComma) && !is(tokenEndId))
        {
            if (is(TokenId::Identifier))
                raiseError(DiagnosticId::parser_err_missing_attribute_sep, ref());
            else
                raiseExpected(DiagnosticId::parser_err_expected_token_before, ref(), TokenId::SymComma);
            skipTo(skipTokens);
            return Result::Error;
        }
        break;

    case AstNodeId::UsingBlock:
        if (!is(tokenEndId) && !tok().startsLine())
        {
            raiseExpected(DiagnosticId::parser_err_expected_token_before, ref(), TokenId::SymComma);
            skipTo(skipTokens);
            return Result::Error;
        }
        break;
        
    case AstNodeId::ArrayLiteral:
    case AstNodeId::UnnamedArgumentBlock:
    case AstNodeId::NamedArgumentBlock:
        if (!consumeIf(TokenId::SymComma) && !is(tokenEndId))
        {
            raiseExpected(DiagnosticId::parser_err_expected_token_before, ref(), TokenId::SymComma);
            skipTo(skipTokens);
            return Result::Error;
        }
        break;

    default:
        break;
    }

    return Result::Success;
}

void Parser::finalizeBlock(AstNodeId blockNodeId, TokenRef openTokRef, TokenRef closeTokenRef, const TokenId tokenEndId, const SmallVector<AstNodeRef>& childrenRefs)
{
    if (childrenRefs.empty())
    {
        switch (blockNodeId)
        {
        case AstNodeId::AttributeBlock:
        {
            const auto diag     = reportError(DiagnosticId::parser_err_empty_attribute, openTokRef);
            const auto tokenEnd = file_->lexOut().token(closeTokenRef);
            diag.last().addSpan(tokenEnd.toLocation(*ctx_, *file_), "");
            diag.report(*ctx_);
            break;
        }
        case AstNodeId::EnumBlock:
        {
            const auto diag     = reportError(DiagnosticId::parser_err_empty_enum, openTokRef);
            const auto tokenEnd = file_->lexOut().token(closeTokenRef);
            diag.last().addSpan(tokenEnd.toLocation(*ctx_, *file_), "");
            diag.report(*ctx_);
            break;
        }
        default:
            break;
        }
    }
}

AstNodeRef Parser::parseBlock(TokenId tokenStartId, AstNodeId blockNodeId)
{
    const Token&   openTok    = tok();
    const TokenRef openTokRef = ref();
    const auto     tokenEndId = Token::toRelated(tokenStartId);

    if (tokenStartId != TokenId::Invalid)
    {
        if (invalid(expectAndConsume(tokenStartId, DiagnosticId::parser_err_expected_token_before)))
            return INVALID_REF;
    }

    SmallVector<AstNodeRef> childrenRefs;
    while (!atEnd() && isNot(tokenEndId))
    {
        const auto loopStartToken = curToken_;
        AstNodeRef childRef       = INVALID_REF;

        // Compiler directives (only in certain blocks)
        childRef = parseBlockCompilerDirective(blockNodeId);
        if (valid(childRef))
        {
            childrenRefs.push_back(childRef);
            continue;
        }

        // One block element
        childRef = parseBlockStmt(blockNodeId);
        if (valid(childRef))
            childrenRefs.push_back(childRef);

        // Separator between statements
        if (parseBlockSeparator(blockNodeId, tokenEndId) == Result::Error)
        {
            if (depthParen_ && is(TokenId::SymRightParen))
                break;
            if (depthBracket_ && is(TokenId::SymRightBracket))
                break;
            if (depthCurly_ && is(TokenId::SymRightCurly))
                break;
        }

        if (loopStartToken == curToken_)
            consume();
    }

    const auto closeTokenRef = ref();
    if (!consumeIf(tokenEndId) && tokenEndId != TokenId::Invalid)
        raiseExpected(DiagnosticId::parser_err_expected_closing, openTokRef, Token::toRelated(openTok.id));

    // Consume end token if necessary
    finalizeBlock(blockNodeId, openTokRef, closeTokenRef, tokenEndId, childrenRefs);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeBlock>(blockNodeId);
    nodePtr->spanChildren   = ast_->store_.push_span(std::span(childrenRefs.data(), childrenRefs.size()));
    return nodeRef;
}

AstNodeRef Parser::parseFile()
{
    return parseBlock(TokenId::Invalid, AstNodeId::File);
}

AstNodeRef Parser::parseNamespace()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Namespace>();
    consume();
    nodePtr->nodeName = parseScopedIdentifier();
    if (invalid(nodePtr->nodeName))
        skipTo({TokenId::SymLeftCurly});
    nodePtr->nodeBody = parseBlock(TokenId::SymLeftCurly, AstNodeId::TopLevelBlock);
    return nodeRef;
}

SWC_END_NAMESPACE()
