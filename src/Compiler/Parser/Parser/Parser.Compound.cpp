#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

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

        case AstNodeId::UnnamedArgumentList:
            return parseExpression();
        case AstNodeId::NamedArgumentList:
            return parseNamedArg();
        case AstNodeId::GenericParamList:
            return parseGenericParam();

        case AstNodeId::ClosureExpr:
            return parseClosureArg();
        case AstNodeId::FunctionExpr:
            return parseLambdaArgumentExpr();
        case AstNodeId::LambdaType:
            return parseLambdaParam();
        case AstNodeId::FunctionParamList:
            return parseFunctionParam();

        case AstNodeId::QuotedListExpr:
            return parseIdentifierSuffixValue();

        case AstNodeId::AliasCallExpr:
            return parseQuotedIdentifier();

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

        case AstNodeId::AttributeList:
        case AstNodeId::UnnamedArgumentList:
        case AstNodeId::NamedArgumentList:
        case AstNodeId::GenericParamList:
        case AstNodeId::FunctionParamList:
        case AstNodeId::ClosureExpr:
        case AstNodeId::FunctionExpr:
        case AstNodeId::LambdaType:
        case AstNodeId::QuotedListExpr:
        case AstNodeId::AliasCallExpr:
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

    return Result::Continue;
}

SpanRef Parser::parseCompoundContent(AstNodeId blockNodeId, TokenId tokenStartId)
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

    return parseCompoundContentInside(blockNodeId, openTokRef, tokenStartId);
}

SpanRef Parser::parseCompoundContentInside(AstNodeId blockNodeId, TokenRef openTokRef, TokenId tokenStartId)
{
    const TokenId tokenEndId = Token::toRelated(tokenStartId);

    // Only blocks whose elements are declarations/statements can host a function
    // declaration, and thus a '#fwd' dual parse. Other compounds (parameter lists,
    // argument lists…) must not disturb the current '#fwd' pass state.
    const bool isStatementBlock = blockNodeId == AstNodeId::TopLevelBlock ||
                                  blockNodeId == AstNodeId::EmbeddedBlock ||
                                  blockNodeId == AstNodeId::AggregateBody ||
                                  blockNodeId == AstNodeId::InterfaceBody;

    SmallVector<AstNodeRef> childrenRefs;
    while (!atEnd() && isNot(tokenEndId))
    {
        const Token* loopStartToken = curToken_;

        // One block element. A statement declaring a function with a '#fwd' parameter is
        // parsed twice: the first pass emits the copy variant ('#fwd' erased), the second
        // pass re-parses the same tokens to emit the move variant ('#fwd' behaves like
        // '#move'). Both variants become ordinary overloads.
        const uint32_t     savedDepthParen   = depthParen_;
        const uint32_t     savedDepthBracket = depthBracket_;
        const uint32_t     savedDepthCurly   = depthCurly_;
        const FwdParseMode savedPassMode     = fwdPassMode_;
        const bool         savedStmtTrigger  = fwdStmtTrigger_;
        if (isStatementBlock)
        {
            fwdPassMode_    = FwdParseMode::Copy;
            fwdStmtTrigger_ = false;
        }

        const AstNodeRef childRef = parseCompoundValue(blockNodeId);
        if (childRef.isValid())
            childrenRefs.push_back(childRef);

        if (isStatementBlock && fwdStmtTrigger_ && childRef.isValid() && curToken_ != loopStartToken)
        {
            const Token*   afterStmtToken    = curToken_;
            const uint32_t afterDepthParen   = depthParen_;
            const uint32_t afterDepthBracket = depthBracket_;
            const uint32_t afterDepthCurly   = depthCurly_;

            curToken_       = loopStartToken;
            depthParen_     = savedDepthParen;
            depthBracket_   = savedDepthBracket;
            depthCurly_     = savedDepthCurly;
            fwdPassMode_    = FwdParseMode::Move;
            fwdStmtTrigger_ = false;

            ++fwdReparseDepth_;
            const AstNodeRef moveVariantRef = parseCompoundValue(blockNodeId);
            --fwdReparseDepth_;
            if (moveVariantRef.isValid())
                childrenRefs.push_back(moveVariantRef);

            // Both passes read the same tokens; realign in case error recovery diverged.
            if (curToken_ != afterStmtToken)
            {
                curToken_     = afterStmtToken;
                depthParen_   = afterDepthParen;
                depthBracket_ = afterDepthBracket;
                depthCurly_   = afterDepthCurly;
            }
        }

        if (isStatementBlock)
        {
            fwdPassMode_    = savedPassMode;
            fwdStmtTrigger_ = savedStmtTrigger;
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
    return ast_->pushSpan(childrenRefs.span());
}

SWC_END_NAMESPACE();
