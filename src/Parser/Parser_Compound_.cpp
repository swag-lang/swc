#include "pch.h"
#include "Core/SmallVector.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCompoundValue(AstNodeId blockNodeId)
{
    switch (blockNodeId)
    {
        case AstNodeId::TopLevelBlock:
            return parseTopLevelStmt();

        case AstNodeId::EmbeddedBlock:
            return parseEmbeddedStmt();

        case AstNodeId::EnumBody:
            return parseEnumValue();
        case AstNodeId::AggregateBody:
            return parseAggregateValue();
        case AstNodeId::InterfaceBody:
            return parseInterfaceValue();

        case AstNodeId::AttributeList:
            return parseAttributeValue();

        case AstNodeId::UnnamedArgList:
            return parseExpression();
        case AstNodeId::NamedArgList:
            return parseNamedArg();
        case AstNodeId::GenericParamList:
            return parseGenericParam();

        case AstNodeId::UsingDecl:
            return parseQualifiedIdentifier();

        case AstNodeId::ClosureExpr:
            return parseClosureCaptureArg();
        case AstNodeId::FunctionExpr:
            return parseLambdaExprArg();
        case AstNodeId::LambdaType:
            return parseLambdaTypeParam();            
        case AstNodeId::FunctionParamList:
            return parseFunctionParam();

        case AstNodeId::MultiPostfixIdentifier:
            return parsePostfixIdentifierValue();

        case AstNodeId::AliasCall:
            return parseIdentifier();

        default:
            SWC_UNREACHABLE();
    }
}

Result Parser::parseCompoundSeparator(AstNodeId blockNodeId, TokenId tokenEndId)
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
        case AstNodeId::TopLevelBlock:
        case AstNodeId::EmbeddedBlock:
            expectEndStatement();
            break;

        case AstNodeId::EnumBody:
            if (consumeIf(TokenId::SymComma).isInvalid() && !is(tokenEndId) && !tok().startsLine())
            {
                raiseExpected(DiagnosticId::parser_err_expected_token_before, ref(), TokenId::SymComma);
                skipTo(skipTokens);
                return Result::Error;
            }
            break;

        case AstNodeId::AggregateBody:
            if (consumeIf(TokenId::SymComma).isInvalid() && consumeIf(TokenId::SymSemiColon).isInvalid() && !is(tokenEndId) && !tok().startsLine())
            {
                raiseExpected(DiagnosticId::parser_err_expected_token_before, ref(), TokenId::SymComma);
                skipTo(skipTokens);
                return Result::Error;
            }
            break;

        case AstNodeId::InterfaceBody:
            if (consumeIf(TokenId::SymSemiColon).isInvalid() && !is(tokenEndId) && !tok().startsLine())
            {
                raiseExpected(DiagnosticId::parser_err_expected_token_before, ref(), TokenId::SymSemiColon);
                skipTo(skipTokens);
                return Result::Error;
            }
            break;

        case AstNodeId::UsingDecl:
        case AstNodeId::AttributeList:
        case AstNodeId::UnnamedArgList:
        case AstNodeId::NamedArgList:
        case AstNodeId::GenericParamList:
        case AstNodeId::FunctionParamList:
        case AstNodeId::ClosureExpr:
        case AstNodeId::FunctionExpr:
        case AstNodeId::LambdaType:
        case AstNodeId::MultiPostfixIdentifier:
        case AstNodeId::AliasCall:
            if (consumeIf(TokenId::SymComma).isInvalid() && !is(tokenEndId))
            {
                raiseExpected(DiagnosticId::parser_err_expected_token_before, ref(), TokenId::SymComma);
                skipTo(skipTokens);
                return Result::Error;
            }
            break;

        default:
            SWC_UNREACHABLE();
    }

    return Result::Success;
}

AstNodeRef Parser::parseCompound(AstNodeId blockNodeId, TokenId tokenStartId, bool endStmt)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstCompound>(blockNodeId);
    nodePtr->spanChildren   = parseCompoundContent(blockNodeId, tokenStartId, endStmt);
    return nodeRef;
}

SpanRef Parser::parseCompoundContent(AstNodeId blockNodeId, TokenId tokenStartId, bool endStmt)
{
    const TokenRef openTokRef = ref();

    if (tokenStartId != TokenId::Invalid)
    {
        if (expectAndConsume(tokenStartId, DiagnosticId::parser_err_expected_token_before).isInvalid())
        {
            if (!skipTo({tokenStartId}))
                return SpanRef::invalid();
            consume();
        }
    }

    return parseCompoundContentInside(blockNodeId, openTokRef, tokenStartId, endStmt);
}

SpanRef Parser::parseCompoundContentInside(AstNodeId blockNodeId, TokenRef openTokRef, TokenId tokenStartId, bool endStmt)
{
    const auto tokenEndId = Token::toRelated(tokenStartId);

    SmallVector<AstNodeRef> childrenRefs;
    while (!atEnd() && isNot(tokenEndId))
    {
        const auto loopStartToken = curToken_;

        // One block element
        AstNodeRef childRef = parseCompoundValue(blockNodeId);
        if (childRef.isValid())
            childrenRefs.push_back(childRef);

        // End of block
        if (endStmt)
        {
            if (is(TokenId::SymSemiColon) || tok().startsLine())
                break;
        }

        // Separator between statements
        if (parseCompoundSeparator(blockNodeId, tokenEndId) == Result::Error)
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

    if (consumeIf(tokenEndId).isInvalid() && tokenEndId != TokenId::Invalid)
        raiseExpected(DiagnosticId::parser_err_expected_closing, openTokRef, Token::toRelated(tokenStartId));

    // Store
    return ast_->store().push_span(childrenRefs.span());
}

SWC_END_NAMESPACE()
