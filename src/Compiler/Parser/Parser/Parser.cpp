#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Memory/MemoryProfile.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseGeneratedValue(const ParserGeneratedMode mode)
{
    switch (mode)
    {
        case ParserGeneratedMode::TopLevel:
            return parseTopLevelStmt();

        case ParserGeneratedMode::Embedded:
            return parseEmbeddedStmt();

        case ParserGeneratedMode::Aggregate:
            return parseAggregateValue();

        case ParserGeneratedMode::Enum:
            return parseEnumValue();
    }

    SWC_UNREACHABLE();
}

AstNodeRef Parser::parseGeneratedContent(const ParserGeneratedMode mode)
{
    SmallVector<AstNodeRef> childrenRefs;
    const TokenRef          containerTokRef = ref();
    const AstNodeId         separatorNodeId = mode == ParserGeneratedMode::Aggregate ? AstNodeId::AggregateBody : mode == ParserGeneratedMode::Enum ? AstNodeId::EnumBody
                                                                                                                                                    : AstNodeId::TopLevelBlock;

    while (!atEnd() && isNot(TokenId::EndOfFile))
    {
        const Token*     loopStartToken = curToken_;
        const AstNodeRef childRef       = parseGeneratedValue(mode);
        if (childRef.isValid())
            childrenRefs.push_back(childRef);

        if (parseCompoundSeparator(separatorNodeId, TokenId::EndOfFile) == Result::Error)
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

    const SpanRef spanChildrenRef = ast_->pushSpan(childrenRefs.span());
    switch (mode)
    {
        case ParserGeneratedMode::TopLevel:
        case ParserGeneratedMode::Embedded:
        {
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::TopLevelBlock>(containerTokRef);
            nodePtr->spanChildrenRef = spanChildrenRef;
            return nodeRef;
        }

        case ParserGeneratedMode::Aggregate:
        {
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::AggregateBody>(containerTokRef);
            nodePtr->spanChildrenRef = spanChildrenRef;
            return nodeRef;
        }

        case ParserGeneratedMode::Enum:
        {
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::EnumBody>(containerTokRef);
            nodePtr->spanChildrenRef = spanChildrenRef;
            return nodeRef;
        }
    }

    SWC_UNREACHABLE();
}

AstNodeRef Parser::parseGenerated(TaskContext& ctx, Ast& ast, SourceView& srcView, const ParserGeneratedMode mode, const TokenRef startTokRef)
{
    SWC_MEM_SCOPE("Frontend/Parser");
#if SWC_HAS_STATS
    Timer time(Stats::timedMetric(Stats::get().timeParser));
#endif

    ctx_ = &ctx;
    ast_ = &ast;

    // Generated parsing temporarily swaps the owner AST source view so token/code
    // locations are wired to the generated snippet. That state lives on the shared
    // AST, so concurrent #ast parses for the same source file must serialize here.
    const std::scoped_lock generatedParseLock(ast_->generatedParseMutex());

    firstToken_     = &srcView.tokens().front();
    lastToken_      = &srcView.tokens().back();
    curToken_       = startTokRef.isValid() ? &srcView.tokens()[startTokRef.get()] : firstToken_;
    depthParen_     = 0;
    depthBracket_   = 0;
    depthCurly_     = 0;
    lastErrorToken_ = TokenRef::invalid();

    SourceView* const previousSrcView = Ast::setThreadSourceViewOverride(&srcView);
    const AstNodeRef  result          = parseGeneratedContent(mode);
    Ast::setThreadSourceViewOverride(previousSrcView);

    return result;
}

void Parser::setReportArguments(Diagnostic& diag, TokenRef tokRef) const
{
    const Token& token = ast_->srcView().token(tokRef);

    if (token.is(TokenId::EndOfFile))
    {
        diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(token.id));
        diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Token::toFamily(token.id));
    }
    else
    {
        diag.addArgument(Diagnostic::ARG_TOK, Diagnostic::tokenErrorString(*ctx_, {ast_->srcView().ref(), tokRef}));
        diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(token.id));
        diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Utf8Helper::addArticleAAn(Token::toFamily(token.id)));
    }

    // Get the last non-trivia token
    if (tokRef.get() != 0)
    {
        const Token& tokenPrev = ast_->srcView().token(tokRef.offset(-1));
        diag.addArgument(Diagnostic::ARG_PREV_TOK, Diagnostic::tokenErrorString(*ctx_, {ast_->srcView().ref(), tokRef.offset(-1)}));
        diag.addArgument(Diagnostic::ARG_PREV_TOK_FAM, Token::toFamily(tokenPrev.id));
        diag.addArgument(Diagnostic::ARG_PREV_A_TOK_FAM, Utf8Helper::addArticleAAn(Token::toFamily(tokenPrev.id)));
    }

    if (tokRef.get() < ast_->srcView().tokens().size() - 1)
    {
        const Token& tokenNext = ast_->srcView().token(tokRef.offset(1));
        diag.addArgument(Diagnostic::ARG_NEXT_TOK, Diagnostic::tokenErrorString(*ctx_, {ast_->srcView().ref(), tokRef.offset(1)}));
        diag.addArgument(Diagnostic::ARG_NEXT_TOK_FAM, Token::toFamily(tokenNext.id));
        diag.addArgument(Diagnostic::ARG_NEXT_A_TOK_FAM, Utf8Helper::addArticleAAn(Token::toFamily(tokenNext.id)));
    }
}

void Parser::setReportExpected(Diagnostic& diag, TokenId expectedTknId)
{
    diag.addArgument(Diagnostic::ARG_EXPECT_TOK, Token::toName(expectedTknId));
    diag.addArgument(Diagnostic::ARG_EXPECT_TOK_FAM, Token::toFamily(expectedTknId));
    diag.addArgument(Diagnostic::ARG_EXPECT_A_TOK_FAM, Utf8Helper::addArticleAAn(Token::toFamily(expectedTknId)));
}

void Parser::setReportSymbol(Diagnostic& diag, TokenRef tokRef) const
{
    if (!tokRef.isValid())
        return;

    diag.addArgument(Diagnostic::ARG_SYM, Diagnostic::tokenErrorString(*ctx_, {ast_->srcView().ref(), tokRef}));
}

Diagnostic Parser::reportExpectedDoBlock(TokenRef tknRefAfterHeader)
{
    Diagnostic diag = reportError(DiagnosticId::parser_err_expected_do_block, tknRefAfterHeader);
    diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, ref()), DiagnosticId::parser_note_controlled_statement, DiagnosticSeverity::Note);
    return diag;
}

Diagnostic Parser::reportUnexpectedDoBlock(TokenRef doTokRef)
{
    Diagnostic diag = reportError(DiagnosticId::parser_err_unexpected_do_block, doTokRef);
    diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, ref()), DiagnosticId::parser_note_block_starts_here, DiagnosticSeverity::Note);
    return diag;
}

Diagnostic Parser::reportEmptySwitchCase(AstNodeRef caseRef, TokenRef boundaryRef, DiagnosticId noteId)
{
    Diagnostic diag = reportError(DiagnosticId::parser_err_empty_case, caseRef);
    if (boundaryRef.isValid() && ast_->srcView().token(boundaryRef).id != TokenId::EndOfFile)
        diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, boundaryRef), noteId, DiagnosticSeverity::Note);
    return diag;
}

Diagnostic Parser::reportEmptySwitchBody(TokenRef openRef, TokenRef closeRef)
{
    Diagnostic diag = reportError(DiagnosticId::parser_err_switch_missing_case, openRef);
    if (closeRef.isValid() && ast_->srcView().token(closeRef).id != TokenId::EndOfFile)
        diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, closeRef), DiagnosticId::parser_note_switch_body_ends_here, DiagnosticSeverity::Note);
    return diag;
}

Diagnostic Parser::reportArgumentCountError(DiagnosticId id, TokenRef calleeRef, TokenRef errorRef, uint32_t expectedCount, uint32_t actualCount, bool atLeast)
{
    Diagnostic diag = reportError(id, errorRef);
    setReportSymbol(diag, calleeRef);
    diag.addArgument(Diagnostic::ARG_COUNT, expectedCount);
    diag.addArgument(Diagnostic::ARG_VALUE, actualCount);
    Utf8 expectedWhat = atLeast ? Utf8("at least ") : Utf8{};
    expectedWhat += std::to_string(expectedCount);
    expectedWhat += expectedCount == 1 ? " argument" : " arguments";
    diag.addArgument(Diagnostic::ARG_WHAT, expectedWhat);
    return diag;
}

Diagnostic Parser::reportArgumentCountError(DiagnosticId id, TokenRef calleeRef, AstNodeRef errorRef, uint32_t expectedCount, uint32_t actualCount, bool atLeast)
{
    Diagnostic diag = reportError(id, errorRef);
    setReportSymbol(diag, calleeRef);
    diag.addArgument(Diagnostic::ARG_COUNT, expectedCount);
    diag.addArgument(Diagnostic::ARG_VALUE, actualCount);
    Utf8 expectedWhat = atLeast ? Utf8("at least ") : Utf8{};
    expectedWhat += std::to_string(expectedCount);
    expectedWhat += expectedCount == 1 ? " argument" : " arguments";
    diag.addArgument(Diagnostic::ARG_WHAT, expectedWhat);
    return diag;
}

void Parser::tryEnhanceUnexpectedToken(Diagnostic& diag, TokenRef tknRef) const
{
    auto expectedOpening = TokenId::Invalid;

    switch (ast_->srcView().token(tknRef).id)
    {
        case TokenId::SymRightParen:
            if (!depthParen_)
                expectedOpening = TokenId::SymLeftParen;
            break;

        case TokenId::SymRightBracket:
            if (!depthBracket_)
                expectedOpening = TokenId::SymLeftBracket;
            break;

        case TokenId::SymRightCurly:
            if (!depthCurly_)
                expectedOpening = TokenId::SymLeftCurly;
            break;

        default:
            break;
    }

    if (expectedOpening == TokenId::Invalid)
        return;

    setReportExpected(diag, expectedOpening);
    if (diag.last().hasSpans())
        diag.last().span(0).messageId = DiagnosticId::parser_note_no_matching_opening;
}

Diagnostic Parser::reportError(DiagnosticId id, TokenRef tknRef)
{
    Diagnostic diag = Diagnostic::get(id, ast_->srcView().fileRef());
    setReportArguments(diag, tknRef);
    diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, tknRef), "");
    if (id == DiagnosticId::parser_err_unexpected_token)
        tryEnhanceUnexpectedToken(diag, tknRef);
    else if (id == DiagnosticId::parser_err_unexpected_and_or)
    {
        if (ast_->srcView().token(tknRef).id == TokenId::SymAmpersandAmpersand)
            diag.addArgument(Diagnostic::ARG_VALUE, "and");
        else if (ast_->srcView().token(tknRef).id == TokenId::SymPipePipe)
            diag.addArgument(Diagnostic::ARG_VALUE, "or");
    }

    if (tknRef == lastErrorToken_)
        diag.setSilent(true);
    lastErrorToken_ = tknRef;

    return diag;
}

Diagnostic Parser::reportError(DiagnosticId id, AstNodeRef nodeRef)
{
    Diagnostic diag = Diagnostic::get(id, ast_->srcView().fileRef());
    if (!nodeRef.isValid())
    {
        const TokenRef tknRef = ref();
        setReportArguments(diag, tknRef);
        diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, tknRef), "");

        if (tknRef == lastErrorToken_)
            diag.setSilent(true);
        lastErrorToken_ = tknRef;
        return diag;
    }

    const AstNode& node   = ast_->node(nodeRef);
    const TokenRef tknRef = node.tokRef();
    setReportArguments(diag, tknRef);
    const SourceCodeRange codeRange = node.codeRangeWithChildren(*ctx_, *ast_);
    diag.last().addSpan(codeRange, "");
    if (id == DiagnosticId::parser_err_unexpected_token)
        tryEnhanceUnexpectedToken(diag, tknRef);
    else if (id == DiagnosticId::parser_err_unexpected_and_or)
    {
        if (ast_->srcView().token(tknRef).id == TokenId::SymAmpersandAmpersand)
            diag.addArgument(Diagnostic::ARG_VALUE, "and");
        else if (ast_->srcView().token(tknRef).id == TokenId::SymPipePipe)
            diag.addArgument(Diagnostic::ARG_VALUE, "or");
    }

    if (tknRef == lastErrorToken_)
        diag.setSilent(true);
    lastErrorToken_ = tknRef;

    return diag;
}

void Parser::raiseError(DiagnosticId id, TokenRef tknRef)
{
    const Diagnostic diag = reportError(id, tknRef);
    diag.report(*ctx_);
}

void Parser::raiseExpected(DiagnosticId id, TokenRef tknRef, TokenId tknExpected)
{
    Diagnostic diag = reportError(id, tknRef);
    setReportExpected(diag, tknExpected);
    if (id == DiagnosticId::parser_err_expected_closing && diag.last().hasSpans())
        diag.last().span(0).messageId = DiagnosticId::parser_note_opening;
    diag.report(*ctx_);
}

bool Parser::skipTo(const SmallVector<TokenId>& targets, SkipUntilFlags flags)
{
    return skip(targets, flags);
}

bool Parser::skipAfter(const SmallVector<TokenId>& targets, SkipUntilFlags flags)
{
    return skip(targets, flags | SkipUntilFlagsE::Consume);
}

bool Parser::skip(const SmallVector<TokenId>& targets, SkipUntilFlags flags)
{
    int            parenDepth   = 0;
    int            bracketDepth = 0;
    int            curlyDepth   = 0;
    const TokenRef refStart     = ref();

    while (!atEnd())
    {
        if (flags.has(SkipUntilFlagsE::EolBefore) && tok().startsLine() && refStart != ref())
            break;

        const bool atTopLevel = (parenDepth | bracketDepth | curlyDepth) == 0;

        if (atTopLevel)
        {
            // Stop at any target token (top level only).
            if (std::ranges::find(targets, id()) != targets.end())
            {
                if (flags.has(SkipUntilFlagsE::Consume))
                    consume();
                return true;
            }
        }

        // Update delimiter depths first (so we won't prematurely stop
        // on a target that appears inside a nested construct).
        switch (id())
        {
            case TokenId::SymLeftParen:
                ++parenDepth;
                break;
            case TokenId::SymRightParen:
                --parenDepth;
                break;
            case TokenId::SymLeftBracket:
            case TokenId::SymAttrStart:
                ++bracketDepth;
                break;
            case TokenId::SymRightBracket:
                --bracketDepth;
                break;
            case TokenId::SymLeftCurly:
                ++curlyDepth;
                break;
            case TokenId::SymRightCurly:
                --curlyDepth;
                break;
            default:
                break;
        }

        // Never let depths go negative (keeps recovery robust even on stray closers).
        parenDepth   = std::max(parenDepth, 0);
        bracketDepth = std::max(bracketDepth, 0);
        curlyDepth   = std::max(curlyDepth, 0);

        consume();
    }

    // Hit EOF without finding a sync point.
    return false;
}

TokenRef Parser::consumeAssert(TokenId id)
{
    SWC_ASSERT(is(id));
    return consume();
}

TokenRef Parser::consume()
{
    if (atEnd())
        return TokenRef::invalid();
    const TokenRef result = ref();
    switch (id())
    {
        case TokenId::SymLeftParen:
            depthParen_++;
            break;
        case TokenId::SymRightParen:
            depthParen_--;
            break;
        case TokenId::SymLeftBracket:
        case TokenId::SymAttrStart:
            depthBracket_++;
            break;
        case TokenId::SymRightBracket:
            depthBracket_--;
            break;
        case TokenId::SymLeftCurly:
            depthCurly_++;
            break;
        case TokenId::SymRightCurly:
            depthCurly_--;
            break;
        default:
            break;
    }

    curToken_++;
    return result;
}

TokenRef Parser::consumeIf(TokenId id)
{
    if (atEnd() || isNot(id))
        return TokenRef::invalid();
    return consume();
}

TokenRef Parser::expectAndConsume(TokenId id, DiagnosticId diagId)
{
    if (is(id))
        return consume();

    Diagnostic diag = reportError(diagId, ref());
    setReportExpected(diag, id);

    if (id == TokenId::Identifier && Token::isSpecialWord(tok().id))
        diag.last().span(0).messageId = DiagnosticId::parser_note_reserved_identifier;

    diag.report(*ctx_);
    return TokenRef::invalid();
}

TokenRef Parser::expectAndConsumeClosing(TokenId closeId, TokenRef openRef, const SmallVector<TokenId>& skipIds, bool skipToEol)
{
    if (is(closeId))
        return consume();

    const TokenId openId = Token::toRelated(closeId);
    const Token&  tok    = ast_->srcView().token(openRef);

    if (tok.id == openId)
    {
        Diagnostic diag = reportError(DiagnosticId::parser_err_expected_closing_before, ref());
        setReportExpected(diag, closeId);
        if (diag.last().hasSpans())
            diag.last().span(0).messageId = DiagnosticId::parser_note_insert_missing_closing;
        diag.last().addSpan(tok.codeRange(*ctx_, ast_->srcView()), DiagnosticId::parser_note_opening, DiagnosticSeverity::Note);
        diag.report(*ctx_);
    }

    SmallVector skip{skipIds};
    if (skip.empty())
    {
        skip.push_back(TokenId::SymSemiColon);
        skip.push_back(TokenId::SymLeftCurly);
    }

    skip.push_back(closeId);
    skipTo(skip, skipToEol ? SkipUntilFlagsE::EolBefore : SkipUntilFlagsE::Zero);

    consumeIf(closeId);
    return TokenRef::invalid();
}

void Parser::expectEndStatement()
{
    if (tok().startsLine() || is(TokenId::EndOfFile))
        return;
    if (isAny(TokenId::SymRightCurly, TokenId::SymRightParen, TokenId::SymRightBracket))
        return;
    if (consumeIf(TokenId::SymSemiColon).isValid())
        return;

    const Diagnostic diag      = reportError(DiagnosticId::parser_err_expected_sep_stmt, ref().offset(-1));
    SourceCodeRange  codeRange = curToken_[-1].codeRange(*ctx_, ast_->srcView());
    codeRange.column += codeRange.len;
    codeRange.offset += codeRange.len;
    codeRange.len = 1;
    diag.last().addSpan(codeRange, "");
    diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, ref()), DiagnosticId::parser_note_next_statement, DiagnosticSeverity::Note);
    diag.report(*ctx_);
    skipTo({TokenId::SymRightCurly, TokenId::SymRightParen, TokenId::SymRightBracket, TokenId::SymSemiColon}, SkipUntilFlagsE::EolBefore);
}

void Parser::parse(TaskContext& ctx, Ast& ast)
{
    SWC_MEM_SCOPE("Frontend/Parser");
#if SWC_HAS_STATS
    Timer time(Stats::timedMetric(Stats::get().timeParser));
#endif

    ctx_ = &ctx;
    ast_ = &ast;

    firstToken_ = &ast_->srcView().tokens().front();
    lastToken_  = &ast_->srcView().tokens().back();
    curToken_   = firstToken_;

    // Force the first node to be invalid, so that AstNodeRef 0 is invalid
    (void) ast_->makeNode<AstNodeId::Invalid>(TokenRef::invalid());

    ast_->setRoot(parseFile());
    ast_->captureParsedNodeBoundary();
}

SWC_END_NAMESPACE();
