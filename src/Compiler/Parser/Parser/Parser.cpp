#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"

SWC_BEGIN_NAMESPACE();

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
        diag.addArgument(Diagnostic::ARG_TOK, Diagnostic::tokenErrorString(*ctx_, SourceCodeRef{ast_->srcView().ref(), tokRef}));
        diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(token.id));
        diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Utf8Helper::addArticleAAn(Token::toFamily(token.id)));
    }

    // Get the last non-trivia token
    if (tokRef.get() != 0)
    {
        const Token& tokenPrev = ast_->srcView().token(tokRef.offset(-1));
        diag.addArgument(Diagnostic::ARG_PREV_TOK, Diagnostic::tokenErrorString(*ctx_, SourceCodeRef{ast_->srcView().ref(), tokRef.offset(-1)}));
        diag.addArgument(Diagnostic::ARG_PREV_TOK_FAM, Token::toFamily(tokenPrev.id));
        diag.addArgument(Diagnostic::ARG_PREV_A_TOK_FAM, Utf8Helper::addArticleAAn(Token::toFamily(tokenPrev.id)));
    }

    if (tokRef.get() < ast_->srcView().tokens().size() - 1)
    {
        const Token& tokenNext = ast_->srcView().token(tokRef.offset(1));
        diag.addArgument(Diagnostic::ARG_NEXT_TOK, Diagnostic::tokenErrorString(*ctx_, SourceCodeRef{ast_->srcView().ref(), tokRef.offset(1)}));
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

Diagnostic Parser::reportError(DiagnosticId id, TokenRef tknRef)
{
    Diagnostic diag = Diagnostic::get(id, ast_->srcView().fileRef());
    setReportArguments(diag, tknRef);
    diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, tknRef), "");

    if (tknRef == lastErrorToken_)
        diag.setSilent(true);
    lastErrorToken_ = tknRef;

    return diag;
}

Diagnostic Parser::reportError(DiagnosticId id, AstNodeRef nodeRef)
{
    Diagnostic     diag   = Diagnostic::get(id, ast_->srcView().fileRef());
    const AstNode& node   = ast_->node(nodeRef);
    const TokenRef tknRef = node.tokRef();
    setReportArguments(diag, tknRef);
    const SourceCodeRange codeRange = node.codeRangeWithChildren(*ctx_, *ast_);
    diag.last().addSpan(codeRange, "");

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
    diag.report(*ctx_);
    skipTo({TokenId::SymRightCurly, TokenId::SymRightParen, TokenId::SymRightBracket, TokenId::SymSemiColon}, SkipUntilFlagsE::EolBefore);
}

void Parser::parse(TaskContext& ctx, Ast& ast)
{
#if SWC_HAS_STATS
    Timer time(&Stats::get().timeParser);
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
