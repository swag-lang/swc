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
    case AstNodeId::ImplEnum:
    case AstNodeId::Impl:
    case AstNodeId::ImplFor:
        return parseTopLevelStmt();

    case AstNodeId::FuncBody:
    case AstNodeId::EmbeddedBlock:
        return parseEmbeddedStmt();

    case AstNodeId::EnumDecl:
        return parseEnumValue();
    case AstNodeId::AggregateBody:
        return parseAggregateValue();

    case AstNodeId::AttributeList:
        return parseAttribute();

    case AstNodeId::ArrayLiteral:
    case AstNodeId::StructLiteral:
    case AstNodeId::UnnamedArgList:
        return parseExpression();

    case AstNodeId::NamedArgList:
        return parseNamedArgument();

    case AstNodeId::GenericParamList:
        return parseGenericParam();

    case AstNodeId::UsingDecl:
        return parseQualifiedIdentifier();

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
        blockNodeId == AstNodeId::ImplEnum ||
        blockNodeId == AstNodeId::Impl ||
        blockNodeId == AstNodeId::ImplFor ||
        blockNodeId == AstNodeId::AggregateBody ||
        blockNodeId == AstNodeId::EnumDecl)
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
    case AstNodeId::EnumDecl:
    case AstNodeId::AggregateBody:
        if (!consumeIf(TokenId::SymComma) && !is(tokenEndId) && !tok().startsLine())
        {
            if (is(TokenId::Identifier) && blockNodeId == AstNodeId::EnumDecl)
                raiseError(DiagnosticId::parser_err_missing_enum_sep, ref());
            else
                raiseExpected(DiagnosticId::parser_err_expected_token_before, ref(), TokenId::SymComma);
            skipTo(skipTokens);
            return Result::Error;
        }
        break;

    case AstNodeId::UsingDecl:
    case AstNodeId::AttributeList:
    case AstNodeId::ArrayLiteral:
    case AstNodeId::StructLiteral:
    case AstNodeId::UnnamedArgList:
    case AstNodeId::NamedArgList:
    case AstNodeId::GenericParamList:
        if (!consumeIf(TokenId::SymComma) && !is(tokenEndId))
        {
            if (is(TokenId::Identifier) && blockNodeId == AstNodeId::AttributeList)
                raiseError(DiagnosticId::parser_err_missing_attribute_sep, ref());
            else
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
        case AstNodeId::AttributeList:
        {
            const auto diag     = reportError(DiagnosticId::parser_err_empty_attribute, openTokRef);
            const auto tokenEnd = file_->lexOut().token(closeTokenRef);
            diag.last().addSpan(tokenEnd.toLocation(*ctx_, *file_), "");
            diag.report(*ctx_);
            break;
        }
        case AstNodeId::EnumDecl:
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

AstNodeRef Parser::parseBlock(AstNodeId blockNodeId, TokenId tokenStartId, bool endStmt)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstCompound>(blockNodeId);
    nodePtr->spanChildren   = parseBlockContent(blockNodeId, tokenStartId, endStmt);
    return nodeRef;
}

Ref Parser::parseBlockContent(AstNodeId blockNodeId, TokenId tokenStartId, bool endStmt)
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

        // End of block
        if (endStmt)
        {
            if (is(TokenId::SymSemiColon) || tok().startsLine())
                break;
        }

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

    // Store
    return ast_->store_.push_span(childrenRefs.span());
}

AstNodeRef Parser::parseFile()
{
    return parseBlock(AstNodeId::File, TokenId::Invalid);
}

AstNodeRef Parser::parseNamespace()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Namespace>();
    consume();
    nodePtr->nodeName = parseQualifiedIdentifier();
    if (invalid(nodePtr->nodeName))
        skipTo({TokenId::SymLeftCurly});
    nodePtr->nodeBody = parseBlock(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
