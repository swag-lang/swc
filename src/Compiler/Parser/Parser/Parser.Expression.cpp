#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // The postfix '!' shares its node with try/catch/expect; only the token tells them apart.
    bool isNotNullExpr(const Ast& ast, AstNodeRef nodeRef)
    {
        const AstNode& node = ast.node(nodeRef);
        return node.is(AstNodeId::ErrorManagementExpr) && ast.srcView().token(node.tokRef()).id == TokenId::SymBang;
    }

    void markCallCalleeNode(Ast& ast, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return;

        AstNode& calleeNode = ast.node(nodeRef);
        switch (calleeNode.id())
        {
            case AstNodeId::Identifier:
                calleeNode.cast<AstIdentifier>().addFlag(AstIdentifierFlagsE::CallCallee);
                break;
            case AstNodeId::MemberAccessExpr:
                calleeNode.cast<AstMemberAccessExpr>().addFlag(AstMemberAccessExprFlagsE::CallCallee);
                break;
            case AstNodeId::AutoMemberAccessExpr:
                calleeNode.cast<AstAutoMemberAccessExpr>().addFlag(AstAutoMemberAccessExprFlagsE::CallCallee);
                break;
            default:
                break;
        }
    }

    bool canStartSubType(TokenId id)
    {
        if (Token::isType(id))
            return true;

        switch (id)
        {
            case TokenId::Identifier:
            case TokenId::KwdStruct:
            case TokenId::KwdUnion:
            case TokenId::KwdFunc:
            case TokenId::KwdMtd:
            case TokenId::CompilerDeclType:
            case TokenId::KwdConst:
            case TokenId::SymAsterisk:
            case TokenId::SymLeftBracket:
            case TokenId::SymLeftParen:
                return true;

            default:
                return false;
        }
    }

    bool looksLikeArrayTypeExpression(const Token* tok, const Token* lastTok)
    {
        SWC_ASSERT(tok);
        if (tok->id != TokenId::SymLeftBracket)
            return false;

        // Disambiguate `[T]`-style type syntax from an array literal without consuming
        // tokens. The decision is intentionally shallow: once the matching ']' is found,
        // only the next token is needed to know whether a subtype follows.
        const Token* cursor = tok;
        uint32_t     depth  = 0;
        while (cursor <= lastTok)
        {
            if (cursor->id == TokenId::SymLeftBracket)
                depth++;
            else if (cursor->id == TokenId::SymRightBracket)
            {
                SWC_ASSERT(depth);
                depth--;
                if (depth == 0)
                    break;
            }

            cursor++;
        }

        if (cursor > lastTok || depth != 0 || cursor == lastTok)
            return false;

        if ((cursor + 1)->startsLine())
            return false;

        return canStartSubType((cursor + 1)->id);
    }

    int getBinaryPrecedence(TokenId id)
    {
        switch (id)
        {
            // Multiplicative
            case TokenId::SymAsterisk:
            case TokenId::SymSlash:
            case TokenId::SymPercent:
                return 40;

                // Additive (including ++ if you treat it as concat/add)
            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymPlusPlus:
                return 30;

                // Shifts
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                return 20;

                // Bitwise AND
            case TokenId::SymAmpersand:
                return 15;

                // Bitwise XOR
            case TokenId::SymCircumflex:
                return 12;

                // Bitwise OR
            case TokenId::SymPipe:
                return 10;

            default:
                return -1; // not a binary operator handled here
        }
    }

    bool isBinaryOperator(TokenId id)
    {
        return Token::isOpArithmeticOrBitwise(id) || id == TokenId::SymPlusPlus;
    }

    int getRelationalPrecedence(TokenId id)
    {
        switch (id)
        {
            // Equality
            case TokenId::SymEqualEqual:
            case TokenId::SymBangEqual:
                return 5;

                // Relational / ordering
            case TokenId::SymLess:
            case TokenId::SymLessEqual:
            case TokenId::SymGreater:
            case TokenId::SymGreaterEqual:
            case TokenId::SymLessEqualGreater:
                return 6;

            default:
                return -1;
        }
    }

    int getLogicalPrecedence(TokenId id)
    {
        switch (id)
        {
            case TokenId::KwdOr:
                return 1;
            case TokenId::KwdAnd:
                return 2;
            default:
                return -1;
        }
    }
}

bool Parser::isClosureCaptureEndPipe() const
{
    if (!is(TokenId::SymPipe) ||
        !hasContextFlag(ParserContextFlagsE::InClosureCapture) ||
        depthParen_ != closureCaptureStopDepthParen_ ||
        depthBracket_ != closureCaptureStopDepthBracket_ ||
        depthCurly_ != closureCaptureStopDepthCurly_ ||
        !nextIs(TokenId::SymLeftParen))
        return false;

    // In `|captures| (params) -> ...`, the second pipe is not a binary/logical operator.
    // Validate the following parameter-list shape before letting expression parsing stop.
    const Token* cursor     = curToken_ + 1;
    uint32_t     parenDepth = 0;
    while (cursor <= lastToken_)
    {
        if (cursor->id == TokenId::SymLeftParen)
        {
            parenDepth++;
        }
        else if (cursor->id == TokenId::SymRightParen)
        {
            SWC_ASSERT(parenDepth);
            parenDepth--;
            if (!parenDepth)
                break;
        }

        cursor++;
    }

    if (cursor >= lastToken_)
        return false;

    const TokenId afterParamListId = (cursor + 1)->id;
    return afterParamListId == TokenId::SymMinusGreater ||
           afterParamListId == TokenId::KwdFail ||
           afterParamListId == TokenId::SymEqualGreater ||
           afterParamListId == TokenId::SymLeftCurly;
}

AstModifierFlags Parser::parseModifiers()
{
    AstModifierFlags                     result = AstModifierFlagsE::Zero;
    std::map<AstModifierFlags, TokenRef> done;

    while (true)
    {
        AstModifierFlags toSet = AstModifierFlagsE::Zero;
        switch (id())
        {
            case TokenId::ModifierBit:
                toSet = AstModifierFlagsE::Bit;
                break;
            case TokenId::ModifierUnConst:
                toSet = AstModifierFlagsE::UnConst;
                break;
            case TokenId::ModifierFail:
                toSet = AstModifierFlagsE::Fail;
                break;
            case TokenId::ModifierNoFail:
                toSet = AstModifierFlagsE::NoFail;
                break;
            case TokenId::ModifierPromote:
                toSet = AstModifierFlagsE::Promote;
                break;
            case TokenId::ModifierWrap:
                toSet = AstModifierFlagsE::Wrap;
                break;
            case TokenId::ModifierNoDrop:
                toSet = AstModifierFlagsE::NoDrop;
                break;
            case TokenId::ModifierComplete:
                toSet = AstModifierFlagsE::Complete;
                break;
            case TokenId::ModifierMove:
                toSet = AstModifierFlagsE::Move;
                break;
            case TokenId::ModifierRelocate:
                toSet = AstModifierFlagsE::Relocate;
                break;
            case TokenId::ModifierFwd:
                // '#fwd' forwards the enclosing function's '#fwd' parameter: it means
                // '#move' in the move variant and erases to nothing in the copy variant.
                if (!fwdDeclActive_)
                {
                    raiseError(DiagnosticId::parser_err_fwd_outside, ref());
                    consume();
                    continue;
                }
                if (fwdCurMode_ == FwdParseMode::Move)
                {
                    toSet = AstModifierFlagsE::Move;
                    break;
                }
                consume();
                continue;
            default:
                break;
        }

        if (toSet == AstModifierFlagsE::Zero)
            break;

        if (result.has(toSet))
        {
            const Diagnostic diag = reportError(DiagnosticId::parser_err_duplicated_modifier, ref());
            diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, done[toSet]), DiagnosticId::parser_note_other_def, DiagnosticSeverity::Note);
            diag.report(*ctx_);
        }

        done[toSet] = ref();
        result.add(toSet);
        consume();
    }

    return result;
}

AstNodeRef Parser::parseBinaryExpr(int minPrecedence)
{
    AstNodeRef left = parsePrefixExpr();
    if (left.isInvalid())
        return AstNodeRef::invalid();

    // Precedence climbing keeps the grammar compact while preserving left associativity:
    // the right side is parsed with a strictly higher minimum precedence.
    while (true)
    {
        const TokenId opId = id();
        if (isClosureCaptureEndPipe())
            break;

        if (!isBinaryOperator(opId))
            break;

        const int precedence = getBinaryPrecedence(opId);
        if (precedence < minPrecedence)
            break;

        const TokenRef tokOp = consume();

        // Modifier flags.
        const AstModifierFlags modifierFlags = parseModifiers();

        // All these operators are left-associative.
        // For right-associative ops, use 'precedence' instead of 'precedence + 1'
        const int nextMinPrecedence = precedence + 1;

        const AstNodeRef right = parseBinaryExpr(nextMinPrecedence);
        if (right.isInvalid())
            return AstNodeRef::invalid();

        // Build the BinaryExpr node
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::BinaryExpr>(tokOp);
        nodePtr->nodeLeftRef          = left;
        nodePtr->modifierFlags        = modifierFlags;
        nodePtr->nodeRightRef         = right;

        // The new node becomes the left side for the next operator
        left = nodeRef;
    }

    return left;
}

AstNodeRef Parser::parseBinaryExpr()
{
    return parseBinaryExpr(0);
}

AstNodeRef Parser::parseCast()
{
    const TokenRef         tknOp         = consume();
    const TokenRef         openRef       = ref();
    const AstModifierFlags modifierFlags = parseModifiers();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    if (consumeIf(TokenId::SymRightParen).isValid())
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AutoCastExpr>(tknOp);
        nodePtr->modifierFlags        = modifierFlags;
        nodePtr->nodeExprRef          = parsePrefixExpr();
        return nodeRef;
    }

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CastExpr>(tknOp);
    nodePtr->addFlag(AstCastExprFlagsE::Explicit);
    nodePtr->modifierFlags = modifierFlags;
    nodePtr->nodeTypeRef   = parseType();
    if (nodePtr->nodeTypeRef.isInvalid())
        skipTo({TokenId::SymRightParen});
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    nodePtr->nodeExprRef = parsePrefixExpr();

    return nodeRef;
}

AstNodeRef Parser::parseExpression()
{
    const AstNodeRef nodeExpr1 = parseLogicalExpr();

    // The conditional family sits above logical expressions and is parsed recursively,
    // making nested `a ? b : c ? d : e` and `or else` chains bind to the right.
    if (is(TokenId::KwdOrElse))
    {
        const TokenRef   tokOp        = consume();
        const AstNodeRef nodeExpr2    = parseExpression();
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::NullCoalescingExpr>(tokOp);
        nodePtr->nodeLeftRef          = nodeExpr1;
        nodePtr->nodeRightRef         = nodeExpr2;
        return nodeRef;
    }

    if (is(TokenId::SymQuestion))
    {
        const TokenRef   tokOp     = consume();
        const AstNodeRef nodeExpr2 = parseExpression();
        expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
        const AstNodeRef nodeExpr3 = parseExpression();

        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ConditionalExpr>(tokOp);
        nodePtr->nodeCondRef          = nodeExpr1;
        nodePtr->nodeTrueRef          = nodeExpr2;
        nodePtr->nodeFalseRef         = nodeExpr3;
        return nodeRef;
    }

    return nodeExpr1;
}

AstNodeRef Parser::parseRangeExpression()
{
    AstNodeRef nodeExpr1 = AstNodeRef::invalid();
    if (!isAny(TokenId::KwdTo, TokenId::KwdUntil))
        nodeExpr1 = parseExpression();

    if (isAny(TokenId::KwdTo, TokenId::KwdUntil))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::RangeExpr>(ref());
        if (is(TokenId::KwdTo))
            nodePtr->addFlag(AstRangeExprFlagsE::Inclusive);
        consume();
        nodePtr->nodeExprDownRef = nodeExpr1;
        nodePtr->nodeExprUpRef   = parseExpression();
        return nodeRef;
    }

    return nodeExpr1;
}

AstNodeRef Parser::parseIdentifierSuffixValue()
{
    if (isAny(TokenId::SymLeftCurly, TokenId::KwdFunc, TokenId::KwdMtd))
        return parseType();
    return parseExpression();
}

AstNodeRef Parser::parseQuotedSingleSuffixValue()
{
    // `Type'Arg` must recognize the same leading type syntax as `Type'(Arg, ...)`.
    // In a type context the suffix is an operand of the enclosing type constructor,
    // so it must leave a following '?' for that constructor: `*Array'u8?` is a nullable
    // pointer to `Array'u8`, while `*Array'(u8?)` explicitly makes the element nullable.
    // A quoted generic may carry a value argument (`Buffer'3`) as well as a type argument.
    // Only type-shaped suffixes need the type parser in a declaration; literals still belong to
    // the generic-expression path.
    if (hasContextFlag(ParserContextFlagsE::InType) && !Token::isLiteral(id()))
        return parseSubType(false);

    if (isAny(TokenId::SymLeftCurly, TokenId::KwdFunc, TokenId::KwdMtd))
        return parseType();

    AstNodeRef nodeRef = parsePrimaryExpression();
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    while (true)
    {
        if (is(TokenId::SymDot) && !tok().flags.has(TokenFlagsE::EolBefore))
        {
            auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::MemberAccessExpr>(consume());
            nodePtr->nodeLeftRef       = nodeRef;
            nodePtr->nodeRightRef      = parseIdentifier();
            nodeRef                    = nodeParent;
            continue;
        }

        if (is(TokenId::SymSingleQuote) && !tok().flags.has(TokenFlagsE::EolBefore))
        {
            const TokenRef tokQuote = consume();
            markCallCalleeNode(*ast_, nodeRef);

            if (is(TokenId::SymLeftParen))
            {
                auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::QuotedListExpr>(tokQuote);
                nodePtr->nodeExprRef       = nodeRef;
                nodePtr->spanChildrenRef   = parseCompoundContent(AstNodeId::QuotedListExpr, TokenId::SymLeftParen);
                nodeRef                    = nodeParent;
                continue;
            }

            auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::QuotedExpr>(tokQuote);
            nodePtr->nodeExprRef       = nodeRef;
            nodePtr->nodeSuffixRef     = parseQuotedSingleSuffixValue();
            nodeRef                    = nodeParent;
            continue;
        }

        break;
    }

    return nodeRef;
}

AstNodeRef Parser::parseIdentifier()
{
    switch (id())
    {
        case TokenId::KwdMe:
        case TokenId::CompilerUniq0:
        case TokenId::CompilerUniq1:
        case TokenId::CompilerUniq2:
        case TokenId::CompilerUniq3:
        case TokenId::CompilerUniq4:
        case TokenId::CompilerUniq5:
        case TokenId::CompilerUniq6:
        case TokenId::CompilerUniq7:
        case TokenId::CompilerUniq8:
        case TokenId::CompilerUniq9:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Identifier>(consume());
            if (hasContextFlag(ParserContextFlagsE::InCompilerDefined))
                nodePtr->addFlag(AstIdentifierFlagsE::InCompilerDefined);
            if (hasContextFlag(ParserContextFlagsE::InClosureCapture))
                nodePtr->addFlag(AstIdentifierFlagsE::InClosureCapture);
            return nodeRef;
        }

        default:
            break;
    }

    const TokenRef tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
    if (tokName.isInvalid())
        return AstNodeRef::invalid();
    auto [identRef, identPtr] = ast_->makeNode<AstNodeId::Identifier>(tokName);
    if (hasContextFlag(ParserContextFlagsE::InCompilerDefined))
        identPtr->addFlag(AstIdentifierFlagsE::InCompilerDefined);
    if (hasContextFlag(ParserContextFlagsE::InClosureCapture))
        identPtr->addFlag(AstIdentifierFlagsE::InClosureCapture);
    return identRef;
}

AstNodeRef Parser::parseQuotedIdentifier()
{
    const AstNodeRef idRef = parseIdentifier();
    if (idRef.isInvalid())
        return AstNodeRef::invalid();

    if (is(TokenId::SymSingleQuote) && !tok().flags.has(TokenFlagsE::EolBefore))
    {
        const TokenRef tokQuote = consume();
        markCallCalleeNode(*ast_, idRef);

        if (is(TokenId::SymLeftParen))
        {
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::QuotedListExpr>(tokQuote);
            nodePtr->nodeExprRef     = idRef;
            nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::QuotedListExpr, TokenId::SymLeftParen);
            return nodeRef;
        }

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::QuotedExpr>(tokQuote);
        nodePtr->nodeExprRef    = idRef;
        nodePtr->nodeSuffixRef  = parseQuotedSingleSuffixValue();
        return nodeRef;
    }

    return idRef;
}

AstNodeRef Parser::parseInitializerExpression(TokenRef tokAssign)
{
    const AstModifierFlags modifierFlags = parseModifiers();
    if (modifierFlags == AstModifierFlagsE::Zero)
        return parseExpression();

    // Anchor the node on its '=', not on the expression that follows: like every other
    // modifier holder ('cast', '+=', 'for', ...) the anchor sits to the LEFT of the
    // modifiers, which is what the diagnostics naming a modifier search from.
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::InitializerExpr>(tokAssign);
    nodePtr->modifierFlags        = modifierFlags;
    nodePtr->nodeExprRef          = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseLogicalExpr(int minPrecedence)
{
    AstNodeRef left = parseRelationalExpr();
    if (left.isInvalid())
        return AstNodeRef::invalid();

    while (true)
    {
        const TokenId opId = id();
        if (!Token::isOpLogical(opId))
            break;

        if (isAny(TokenId::SymAmpersandAmpersand, TokenId::SymPipePipe))
            raiseError(DiagnosticId::parser_err_unexpected_and_or, ref());

        const int precedence = getLogicalPrecedence(opId);
        if (precedence < minPrecedence)
            break;

        const TokenRef tokOp             = consume();
        const int      nextMinPrecedence = precedence + 1;

        const AstNodeRef right = parseLogicalExpr(nextMinPrecedence);
        if (right.isInvalid())
            return AstNodeRef::invalid();

        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LogicalExpr>(tokOp);
        nodePtr->nodeLeftRef          = left;
        nodePtr->nodeRightRef         = right;
        left                          = nodeRef;
    }

    return left;
}

AstNodeRef Parser::parseLogicalExpr()
{
    return parseLogicalExpr(0);
}

AstNodeRef Parser::parseNamedArg()
{
    // The name
    if (is(TokenId::Identifier) && nextIs(TokenId::SymColon) && !tok().flags.has(TokenFlagsE::BlankAfter))
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::NamedArgument>(consume());
        consumeAssert(TokenId::SymColon);
        nodePtr->nodeArgRef = parseExpression();
        return nodeRef;
    }

    // The argument
    return parseExpression();
}

AstNodeRef Parser::parseParenExpr()
{
    const TokenRef openRef        = ref();
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ParenExpr>(consume());
    nodePtr->nodeExprRef          = parseExpression();
    if (nodePtr->nodeExprRef.isInvalid())
        skipTo({TokenId::SymRightParen}, SkipUntilFlagsE::EolBefore);
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parsePostFixExpression()
{
    AstNodeRef nodeRef = parsePrimaryExpression();
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    // Postfix operations are greedily folded into the left expression. The blank/EOL
    // checks are semantic: they prevent accidental calls/indexes/member accesses across
    // token boundaries where the language expects a new expression.
    TokenRef firstOptionalAccessTokRef = TokenRef::invalid();
    while (true)
    {
        // Not-null assertion. Recognized here rather than lexed, because in PREFIX position
        // the same character is the logical negation ('if !.buffer do'); only a postfix '!'
        // opens the assertion, and a postfix '!' has no other meaning. Being postfix, it
        // binds tighter than every prefix form and chains with '.', '[' and '('.
        if (is(TokenId::SymBang) && !tok().flags.hasAny({TokenFlagsE::EolBefore, TokenFlagsE::BlankBefore}))
        {
            auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::ErrorManagementExpr>(consume());
            nodePtr->nodeExprRef       = nodeRef;
            nodeRef                    = nodeParent;
            continue;
        }

        // Scope resolution
        if ((is(TokenId::SymDot) || is(TokenId::SymQuestionDot)) && !tok().flags.has(TokenFlagsE::EolBefore))
        {
            const bool optionalAccess  = is(TokenId::SymQuestionDot);
            auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::MemberAccessExpr>(consume());
            nodePtr->nodeLeftRef       = nodeRef;
            nodePtr->nodeRightRef      = parseIdentifier();
            if (optionalAccess)
            {
                nodePtr->addFlag(AstMemberAccessExprFlagsE::OptionalAccess);
                if (firstOptionalAccessTokRef.isInvalid())
                    firstOptionalAccessTokRef = nodePtr->tokRef();
            }
            nodeRef = nodeParent;
            continue;
        }

        // Array indexing or slicing
        if (is(TokenId::SymLeftBracket) && !tok().flags.has(TokenFlagsE::BlankBefore))
        {
            nodeRef = parseArraySlicingIndex(nodeRef);
            continue;
        }

        // Function call
        if (is(TokenId::SymLeftParen) && !tok().flags.has(TokenFlagsE::BlankBefore))
        {
            nodeRef = parseFunctionArguments(nodeRef);
            continue;
        }

        // Struct init: A{args}
        if (is(TokenId::SymLeftCurly) && !tok().flags.has(TokenFlagsE::BlankBefore))
        {
            nodeRef = parseInitializerList(nodeRef);
            continue;
        }

        // Quote
        if (is(TokenId::SymSingleQuote) && !tok().flags.has(TokenFlagsE::EolBefore))
        {
            const TokenRef tokQuote = consume();
            markCallCalleeNode(*ast_, nodeRef);

            if (is(TokenId::SymLeftParen))
            {
                auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::QuotedListExpr>(tokQuote);
                nodePtr->nodeExprRef       = nodeRef;
                nodePtr->spanChildrenRef   = parseCompoundContent(AstNodeId::QuotedListExpr, TokenId::SymLeftParen);
                nodeRef                    = nodeParent;
                continue;
            }

            auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::QuotedExpr>(tokQuote);
            nodePtr->nodeExprRef       = nodeRef;
            nodePtr->nodeSuffixRef     = parseQuotedSingleSuffixValue();
            nodeRef                    = nodeParent;
            continue;
        }

        break;
    }

    // A '?.' anywhere in the chain gives the whole postfix chain a null short-circuit
    // outcome: wrap it so sema and codegen have a single anchor for the null exit.
    if (firstOptionalAccessTokRef.isValid())
    {
        auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::OptionalChainExpr>(firstOptionalAccessTokRef);
        nodePtr->nodeExprRef       = nodeRef;
        nodeRef                    = nodeParent;
    }

    // 'as'
    if (is(TokenId::KwdAs))
    {
        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::AsCastExpr>(consume());
        nodePtr->nodeExprRef             = nodeRef;
        nodePtr->nodeTypeRef             = parseType();
        return nodeParent;
    }

    // 'is'
    if (is(TokenId::KwdIs))
    {
        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::IsTypeExpr>(consume());
        nodePtr->nodeExprRef             = nodeRef;
        nodePtr->nodeTypeRef             = parseType();
        return nodeParent;
    }

    return nodeRef;
}

AstNodeRef Parser::parseAutoMemberAccessExpr()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AutoMemberAccessExpr>(consume());
    nodePtr->nodeIdentRef   = parseIdentifier();
    if (hasContextFlag(ParserContextFlagsE::InCallArgument))
        nodePtr->addFlag(AstAutoMemberAccessExprFlagsE::CallArgument);
    return nodeRef;
}

AstNodeRef Parser::parsePrimaryExpression()
{
    switch (id())
    {
        case TokenId::SymDot:
            return parseAutoMemberAccessExpr();

        case TokenId::CompilerTypeOf:
        case TokenId::CompilerKindOf:
            return parseCompilerTypeOf();

        case TokenId::CompilerSizeOf:
        case TokenId::CompilerAlignOf:
        case TokenId::CompilerOffsetOf:
        case TokenId::CompilerDeclType:
        case TokenId::CompilerStringOf:
        case TokenId::CompilerNameOf:
        case TokenId::CompilerFullNameOf:
        case TokenId::CompilerRunes:
        case TokenId::CompilerIsConstExpr:
        case TokenId::CompilerDefined:
        case TokenId::CompilerInclude:
        case TokenId::CompilerSafety:
        case TokenId::CompilerSanity:
        case TokenId::CompilerHasTag:
        case TokenId::CompilerInject:
        case TokenId::CompilerLocation:
            return parseCompilerCallOne();

        case TokenId::CompilerGetTag:
            return parseCompilerCall(3);

        case TokenId::CompilerRun:
            return parseCompilerRun();
        case TokenId::CompilerCode:
            return parseCompilerCode();

        case TokenId::KwdTry:
        case TokenId::KwdCatch:
        case TokenId::KwdExpect:
            return parseErrorManagementExpr();

        case TokenId::IntrinsicKindOf:
        case TokenId::IntrinsicCountOf:
        case TokenId::IntrinsicDataOf:
            return parseIntrinsicCall(1);

        case TokenId::IntrinsicMakeAny:
        case TokenId::IntrinsicMakeSlice:
        case TokenId::IntrinsicMakeString:
        case TokenId::IntrinsicIs:
        case TokenId::IntrinsicTableOf:
            return parseIntrinsicCall(2);

        case TokenId::IntrinsicMakeInterface:
        case TokenId::IntrinsicAs:
            return parseIntrinsicCall(3);

        case TokenId::IntrinsicCompiler:
        case TokenId::IntrinsicRtFlags:
        case TokenId::IntrinsicProcessInfos:
        case TokenId::IntrinsicArgs:
        case TokenId::IntrinsicModules:
        case TokenId::IntrinsicGvtd:
        case TokenId::IntrinsicJit:
            return parseIntrinsicCallConstantExpr();

        case TokenId::IntrinsicGetContext:
            return parseIntrinsicCallExpr(0);

        case TokenId::IntrinsicAbs:
        case TokenId::IntrinsicSqrt:
        case TokenId::IntrinsicSin:
        case TokenId::IntrinsicCos:
        case TokenId::IntrinsicTan:
        case TokenId::IntrinsicSinh:
        case TokenId::IntrinsicCosh:
        case TokenId::IntrinsicTanh:
        case TokenId::IntrinsicASin:
        case TokenId::IntrinsicACos:
        case TokenId::IntrinsicATan:
        case TokenId::IntrinsicLog:
        case TokenId::IntrinsicLog2:
        case TokenId::IntrinsicLog10:
        case TokenId::IntrinsicFloor:
        case TokenId::IntrinsicCeil:
        case TokenId::IntrinsicTrunc:
        case TokenId::IntrinsicRound:
        case TokenId::IntrinsicExp:
        case TokenId::IntrinsicExp2:
        case TokenId::IntrinsicByteSwap:
        case TokenId::IntrinsicBitCountNz:
        case TokenId::IntrinsicBitCountTz:
        case TokenId::IntrinsicBitCountLz:
        case TokenId::IntrinsicVecSplat:
        case TokenId::IntrinsicVecWidenLo:
        case TokenId::IntrinsicVecWidenHi:
        case TokenId::IntrinsicVecMask:
        case TokenId::IntrinsicVecAny:
        case TokenId::IntrinsicVecAll:
        case TokenId::IntrinsicVecReduceAdd:
        case TokenId::IntrinsicVecReduceMin:
        case TokenId::IntrinsicVecReduceMax:
        case TokenId::IntrinsicVecReduceAnd:
        case TokenId::IntrinsicVecReduceOr:
        case TokenId::IntrinsicVecReduceXor:
        case TokenId::IntrinsicVecTruncS32:
        case TokenId::IntrinsicAtomicGet:
            return parseIntrinsicCallExpr(1);

        case TokenId::IntrinsicStringCmp:
        case TokenId::IntrinsicMin:
        case TokenId::IntrinsicMax:
        case TokenId::IntrinsicRol:
        case TokenId::IntrinsicRor:
        case TokenId::IntrinsicPow:
        case TokenId::IntrinsicATan2:
        case TokenId::IntrinsicAtomicXchg:
        case TokenId::IntrinsicAtomicXor:
        case TokenId::IntrinsicAtomicOr:
        case TokenId::IntrinsicAtomicAnd:
        case TokenId::IntrinsicAtomicAdd:
        case TokenId::IntrinsicVecSatAdd:
        case TokenId::IntrinsicVecSatSub:
        case TokenId::IntrinsicVecPackUS:
        case TokenId::IntrinsicVecPackSS:
        case TokenId::IntrinsicVecInterleaveLo:
        case TokenId::IntrinsicVecInterleaveHi:
        case TokenId::IntrinsicVecAvgR:
        case TokenId::IntrinsicVecMadd:
        case TokenId::IntrinsicVecMaddUBS:
        case TokenId::IntrinsicVecSad:
        case TokenId::IntrinsicVecMulHi:
        case TokenId::IntrinsicVecGather:
        case TokenId::IntrinsicVecPerm:
        case TokenId::IntrinsicVecShuffle:
            return parseIntrinsicCallExpr(2);

        case TokenId::IntrinsicMemCmp:
        case TokenId::IntrinsicTypeCmp:
        case TokenId::IntrinsicAtomicCmpXchg:
        case TokenId::IntrinsicMulAdd:
        case TokenId::IntrinsicVecShuffle2:
        case TokenId::IntrinsicVecAlign:
        case TokenId::IntrinsicVecSelect:
            return parseIntrinsicCallExpr(3);

        case TokenId::NumberInteger:
        case TokenId::NumberBin:
        case TokenId::NumberHex:
        case TokenId::NumberFloat:
        case TokenId::Character:
            return parseLiteralExpression();

        case TokenId::StringLine:
        case TokenId::StringMultiLine:
        case TokenId::KwdTrue:
        case TokenId::KwdFalse:
        case TokenId::KwdNull:
            return parseLiteral();

        case TokenId::ModifierRaw:
            return parseRawStringLiteral();

        case TokenId::CompilerFile:
        case TokenId::CompilerModule:
        case TokenId::CompilerLine:
        case TokenId::CompilerSwcVersion:
        case TokenId::CompilerSwcRevision:
        case TokenId::CompilerSwcBuildNum:
        case TokenId::CompilerBuildCfg:
        case TokenId::CompilerCommand:
        case TokenId::CompilerCallerLocation:
        case TokenId::CompilerOs:
        case TokenId::CompilerArch:
        case TokenId::CompilerCpu:
        case TokenId::CompilerSwagOs:
        case TokenId::CompilerScopeName:
        case TokenId::CompilerCurLocation:
            return parseLiteral();

        case TokenId::SymLeftParen:
            return parseParenExpr();

        case TokenId::SymLeftCurly:
            return parseLiteralStruct();

        case TokenId::SymLeftBracket:
            // `[ ... ]` is the only primary form shared by type syntax and value
            // syntax. Prefer type parsing only when a type-only prefix or the
            // non-consuming shape check proves it.
            if (nextIs(TokenId::SymDotDot) || nextIs(TokenId::SymQuestion) || nextIs(TokenId::SymAsterisk))
                return parseType();
            if (looksLikeArrayTypeExpression(tokPtr(), lastToken_))
                return parseType();
            return parseLiteralArray();

        case TokenId::TypeAny:
        case TokenId::TypeCString:
        case TokenId::TypeString:
        case TokenId::TypeTypeInfo:
        case TokenId::TypeVoid:
        case TokenId::TypeBool:
        case TokenId::TypeS8:
        case TokenId::TypeS16:
        case TokenId::TypeS32:
        case TokenId::TypeS64:
        case TokenId::TypeU8:
        case TokenId::TypeU16:
        case TokenId::TypeU32:
        case TokenId::TypeU64:
        case TokenId::TypeRune:
        case TokenId::TypeF32:
        case TokenId::TypeF64:
        case TokenId::KwdConst:
        case TokenId::KwdStruct:
        case TokenId::KwdUnion:
        case TokenId::SymAsterisk:
            return parseType();

        case TokenId::CompilerType:
            return parseCompilerTypeExpr();

        case TokenId::Identifier:
        {
            AstNodeRef nodeRef = parseQuotedIdentifier();

            // A named type used as a type-value in an expression (most visibly on the right of
            // '#typeof(x) == T?') still owns its postfix nullability. The suffix is deliberately
            // adjacent, so ordinary ternaries retain their spaced spelling.
            if (is(TokenId::SymQuestion) && !tok().flags.has(TokenFlagsE::BlankBefore))
            {
                auto [nullableRef, nullablePtr] = ast_->makeNode<AstNodeId::QualifiedType>(consume());
                nullablePtr->nodeTypeRef        = nodeRef;
                nullablePtr->addFlag(AstQualifiedTypeFlagsE::Nullable);
                nodeRef = nullableRef;
            }

            return nodeRef;
        }
        case TokenId::KwdMe:
        case TokenId::CompilerUniq0:
        case TokenId::CompilerUniq1:
        case TokenId::CompilerUniq2:
        case TokenId::CompilerUniq3:
        case TokenId::CompilerUniq4:
        case TokenId::CompilerUniq5:
        case TokenId::CompilerUniq6:
        case TokenId::CompilerUniq7:
        case TokenId::CompilerUniq8:
        case TokenId::CompilerUniq9:
            return parseIdentifier();

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseLambdaExpression();

        default:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            return AstNodeRef::invalid();
    }
}

AstNodeRef Parser::parseQualifiedIdentifier()
{
    AstNodeRef leftNodeRef = parseQuotedIdentifier();
    if (leftNodeRef.isInvalid())
        return AstNodeRef::invalid();

    while (!tok().startsLine() && is(TokenId::SymDot))
    {
        const TokenRef tokDot = consume();

        const AstNodeRef rightNodeRef = parseQuotedIdentifier();
        if (rightNodeRef.isInvalid())
            return AstNodeRef::invalid();

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::MemberAccessExpr>(tokDot);
        nodePtr->nodeLeftRef    = leftNodeRef;
        nodePtr->nodeRightRef   = rightNodeRef;

        leftNodeRef = nodeRef;
    }

    return leftNodeRef;
}

AstNodeRef Parser::parseRelationalExpr(int minPrecedence)
{
    // Relational operators are separated from arithmetic binary operators so chained
    // comparisons keep their own AST kind and diagnostics.
    AstNodeRef left = parseBinaryExpr();
    if (left.isInvalid())
        return AstNodeRef::invalid();

    while (true)
    {
        const TokenId opId = id();
        if (!Token::isOpRelational(opId))
            break;

        const int precedence = getRelationalPrecedence(opId);
        if (precedence < minPrecedence)
            break;

        const TokenRef tokOp = consume();

        const int nextMinPrecedence = precedence + 1;

        const AstNodeRef right = parseRelationalExpr(nextMinPrecedence);
        if (right.isInvalid())
            return AstNodeRef::invalid();

        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::RelationalExpr>(tokOp);
        nodePtr->nodeLeftRef          = left;
        nodePtr->nodeRightRef         = right;

        left = nodeRef;
    }

    return left;
}

AstNodeRef Parser::parseRelationalExpr()
{
    return parseRelationalExpr(0);
}

AstNodeRef Parser::parsePrefixExpr()
{
    switch (id())
    {
        case TokenId::KwdCast:
            return parseCast();

        case TokenId::ModifierMove:
        case TokenId::SymAmpersand:
        {
            const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::UnaryExpr>(consume());
            nodePtr->nodeExprRef            = parsePrefixExpr();
            return nodeParen;
        }

        case TokenId::ModifierFwd:
        {
            // '#fwd expr' forwards a '#fwd' parameter: '#move expr' in the move variant,
            // plain 'expr' in the copy variant.
            if (!fwdDeclActive_)
            {
                raiseError(DiagnosticId::parser_err_fwd_outside, ref());
                consume();
                return parsePrefixExpr();
            }
            if (fwdCurMode_ == FwdParseMode::Move)
            {
                const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::UnaryExpr>(consume());
                nodePtr->nodeExprRef            = parsePrefixExpr();
                return nodeParen;
            }
            consume();
            return parsePrefixExpr();
        }

        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymBang:
        case TokenId::SymTilde:
        {
            const TokenRef tokOp = consume();
            if (isAny(TokenId::SymPlus, TokenId::SymMinus, TokenId::SymBang, TokenId::SymTilde))
            {
                const Diagnostic diag = reportError(DiagnosticId::parser_err_unexpected_token, ref());
                diag.report(*ctx_);
                consume();
            }

            const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::UnaryExpr>(tokOp);
            nodePtr->nodeExprRef            = parsePrefixExpr();
            return nodeParen;
        }

        default:
            return parsePostFixExpression();
    }
}

AstNodeRef Parser::parseInitializerList(AstNodeRef nodeWhat)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::StructInitializerList>(ref());
    nodePtr->nodeWhatRef    = nodeWhat;
    nodePtr->spanArgsRef    = parseCompoundContent(AstNodeId::NamedArgumentList, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseErrorManagementExpr()
{
    const TokenRef opTokRef = consume();
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ErrorManagementExpr>(opTokRef);
    nodePtr->nodeExprRef    = parseExpression();

    // 'let x = catch f() as err' captures the caught error into a named local (enclosing scope):
    // 'x' is the result, 'err' the error. Only 'catch' captures. parseExpression() absorbed the
    // trailing 'as err' into the operand as an 'AsCastExpr'; unwrap it into operand + bound name.
    // (A trailing 'as T' on try/expect stays an ordinary cast of the operand.)
    if (ast_->srcView().token(opTokRef).id == TokenId::KwdCatch &&
        nodePtr->nodeExprRef.isValid() &&
        ast_->node(nodePtr->nodeExprRef).is(AstNodeId::AsCastExpr))
    {
        const auto& asCast     = ast_->node(nodePtr->nodeExprRef).cast<AstAsCastExpr>();
        nodePtr->errNameTokRef = ast_->node(asCast.nodeTypeRef).tokRef();
        nodePtr->nodeExprRef   = asCast.nodeExprRef;
    }

    // 'expect f()!' asserts the RESULT is not null, not the fallible call. These keywords
    // already swallow everything to their right, so parseExpression() folded the '!' onto
    // the operand; hoist it back out. Explicit parentheses still give the inner reading.
    if (nodePtr->nodeExprRef.isValid() && isNotNullExpr(*ast_, nodePtr->nodeExprRef))
    {
        auto&      inner      = ast_->node(nodePtr->nodeExprRef).cast<AstErrorManagementExpr>();
        const auto notNullRef = nodePtr->nodeExprRef;
        nodePtr->nodeExprRef  = inner.nodeExprRef;
        inner.nodeExprRef     = nodeRef;
        return notNullRef;
    }

    return nodeRef;
}

AstNodeRef Parser::parseArraySlicingIndex(AstNodeRef nodeRef)
{
    const TokenRef openRef = consumeAssert(TokenId::SymLeftBracket);

    // 'expr[]' opens the pointed box: the whole-value read/write place, the postfix
    // spelling of the dereference.
    if (is(TokenId::SymRightBracket))
    {
        consume();
        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::UnaryExpr>(openRef);
        nodePtr->nodeExprRef             = nodeRef;
        return nodeParent;
    }

    // 'expr[as T]' reinterprets the pointed storage as a T and opens it.
    if (is(TokenId::KwdAs))
    {
        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::CastExpr>(consume());
        nodePtr->addFlag(AstCastExprFlagsE::Explicit);
        nodePtr->addFlag(AstCastExprFlagsE::DerefPlace);
        nodePtr->nodeTypeRef = parseType();
        nodePtr->nodeExprRef = nodeRef;
        expectAndConsumeClosing(TokenId::SymRightBracket, openRef);
        return nodeParent;
    }

    const TokenRef tokStart = ref();
    AstNodeRef     nodeExpr = AstNodeRef::invalid();
    if (!isAny(TokenId::KwdTo, TokenId::KwdUntil))
        nodeExpr = parseExpression();

    if (!isAny(TokenId::KwdTo, TokenId::KwdUntil))
    {
        SmallVector<AstNodeRef> nodeArgs;
        nodeArgs.push_back(nodeExpr);
        while (consumeIf(TokenId::SymComma).isValid())
        {
            nodeExpr = parseExpression();
            if (nodeExpr.isInvalid())
                return AstNodeRef::invalid();
            nodeArgs.push_back(nodeExpr);
        }

        expectAndConsumeClosing(TokenId::SymRightBracket, openRef);

        if (nodeArgs.size() == 1)
        {
            const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::IndexExpr>(tokStart);
            nodePtr->nodeExprRef             = nodeRef;
            nodePtr->nodeArgRef              = nodeExpr;
            return nodeParent;
        }

        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::IndexListExpr>(tokStart);
        nodePtr->nodeExprRef             = nodeRef;
        nodePtr->spanChildrenRef         = ast_->pushSpan(nodeArgs.span());
        return nodeParent;
    }

    // Slicing
    const auto [rangeRef, rangePtr] = ast_->makeNode<AstNodeId::RangeExpr>(tokStart);
    if (is(TokenId::KwdTo))
        rangePtr->addFlag(AstRangeExprFlagsE::Inclusive);
    consume();
    rangePtr->nodeExprDownRef = nodeExpr;
    if (!is(TokenId::SymRightBracket))
        rangePtr->nodeExprUpRef = parseExpression();
    else
        rangePtr->nodeExprUpRef.setInvalid();

    expectAndConsumeClosing(TokenId::SymRightBracket, openRef);

    const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::IndexExpr>(tokStart);
    nodePtr->nodeExprRef             = nodeRef;
    nodePtr->nodeArgRef              = rangeRef;
    return nodeParent;
}

AstNodeRef Parser::parseFail()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FailExpr>(consume());
    nodePtr->nodeExprRef    = parseExpression();
    return nodeRef;
}

SWC_END_NAMESPACE();
