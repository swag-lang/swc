#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::string_view autoInlineCallName(const Ast& ast, AstNodeRef nodeRef)
    {
        while (nodeRef.isValid() && ast.hasNode(nodeRef))
        {
            const AstNode& node = ast.node(nodeRef);
            if (const auto* call = node.safeCast<AstCallExpr>())
            {
                nodeRef = call->nodeExprRef;
                continue;
            }
            if (node.is(AstNodeId::Identifier))
                return ast.srcView().tokenString(node.tokRef());
            if (const auto* member = node.safeCast<AstMemberAccessExpr>())
            {
                nodeRef = member->nodeRightRef;
                continue;
            }
            if (const auto* member = node.safeCast<AstAutoMemberAccessExpr>())
            {
                nodeRef = member->nodeIdentRef;
                continue;
            }

            break;
        }

        return {};
    }

    class AutoInlineCallGraph
    {
    public:
        void addFunction(const Ast& ast, const AstFunctionDecl& decl)
        {
            if (decl.tokNameRef.isInvalid())
                return;

            const uint32_t sourceIndex = indexOf(ast.srcView().tokenString(decl.tokNameRef));
            Ast::visit(ast, decl.nodeBodyRef, [&](AstNodeRef, const AstNode& node) {
                if (node.is(AstNodeId::FunctionDecl))
                    return Ast::VisitResult::Skip;

                const auto* call = node.safeCast<AstCallExpr>();
                if (!call)
                    return Ast::VisitResult::Continue;

                const std::string_view targetName = autoInlineCallName(ast, call->nodeExprRef);
                if (!targetName.empty())
                {
                    const uint32_t targetIndex = indexOf(targetName);
                    if (std::ranges::find(edges_[sourceIndex], targetIndex) == edges_[sourceIndex].end())
                        edges_[sourceIndex].push_back(targetIndex);
                }
                return Ast::VisitResult::Continue;
            });
        }

        void findCycles()
        {
            indices_.assign(edges_.size(), UINT32_MAX);
            lowLinks_.resize(edges_.size());
            onStack_.assign(edges_.size(), false);
            cyclic_.assign(edges_.size(), false);
            for (uint32_t i = 0; i < edges_.size(); ++i)
            {
                if (indices_[i] == UINT32_MAX)
                    connect(i);
            }
        }

        bool isCyclic(const std::string_view name) const
        {
            const auto it = nameIndices_.find(name);
            return it != nameIndices_.end() && cyclic_[it->second];
        }

        bool callsAny(const std::string_view name, const std::unordered_set<std::string_view>& targets) const
        {
            const auto sourceIt = nameIndices_.find(name);
            if (sourceIt == nameIndices_.end())
                return false;

            for (const std::string_view target : targets)
            {
                const auto targetIt = nameIndices_.find(target);
                if (targetIt != nameIndices_.end() &&
                    std::ranges::find(edges_[sourceIt->second], targetIt->second) != edges_[sourceIt->second].end())
                    return true;
            }
            return false;
        }

    private:
        uint32_t indexOf(const std::string_view name)
        {
            const auto [it, inserted] = nameIndices_.try_emplace(name, static_cast<uint32_t>(edges_.size()));
            if (inserted)
                edges_.emplace_back();
            return it->second;
        }

        void connect(const uint32_t nodeIndex)
        {
            indices_[nodeIndex]  = nextIndex_;
            lowLinks_[nodeIndex] = nextIndex_;
            nextIndex_++;
            stack_.push_back(nodeIndex);
            onStack_[nodeIndex] = true;

            for (const uint32_t targetIndex : edges_[nodeIndex])
            {
                if (indices_[targetIndex] == UINT32_MAX)
                {
                    connect(targetIndex);
                    lowLinks_[nodeIndex] = std::min(lowLinks_[nodeIndex], lowLinks_[targetIndex]);
                }
                else if (onStack_[targetIndex])
                    lowLinks_[nodeIndex] = std::min(lowLinks_[nodeIndex], indices_[targetIndex]);
            }

            if (lowLinks_[nodeIndex] != indices_[nodeIndex])
                return;

            SmallVector<uint32_t> component;
            for (;;)
            {
                const uint32_t memberIndex = stack_.back();
                stack_.pop_back();
                onStack_[memberIndex] = false;
                component.push_back(memberIndex);
                if (memberIndex == nodeIndex)
                    break;
            }

            const bool selfCycle = component.size() == 1 && std::ranges::find(edges_[nodeIndex], nodeIndex) != edges_[nodeIndex].end();
            if (component.size() > 1 || selfCycle)
            {
                for (const uint32_t memberIndex : component)
                    cyclic_[memberIndex] = true;
            }
        }

        std::unordered_map<std::string_view, uint32_t> nameIndices_;
        std::vector<SmallVector<uint32_t>>             edges_;
        std::vector<uint32_t>                          indices_;
        std::vector<uint32_t>                          lowLinks_;
        std::vector<bool>                              onStack_;
        std::vector<bool>                              cyclic_;
        SmallVector<uint32_t>                          stack_;
        uint32_t                                       nextIndex_ = 0;
    };

    // Generated snippets arrive after the module-wide parse barrier, while sema may already be
    // reading the owner Ast. Preserve the former leaf-only decision within the fresh root instead
    // of consulting or mutating the concurrently analysed module graph.
    void finalizeGeneratedAutoInlineCandidates(Ast& ast, const AstNodeRef rootRef)
    {
        Ast::visit(ast, rootRef, [&](AstNodeRef nodeRef, const AstNode& node) {
            const auto* decl = node.safeCast<AstFunctionDecl>();
            if (!decl || decl->autoInlineCost > K_AUTO_INLINE_MAX_BODY_TOKENS)
                return Ast::VisitResult::Continue;

            if (!decl->hasFlag(AstFunctionFlagsE::AutoInlineHasCalls))
                ast.node<AstNodeId::FunctionDecl>(nodeRef)->addFlag(AstFunctionFlagsE::AutoInlineBody);
            return Ast::VisitResult::Continue;
        });
    }

    void collectMetaFunctionNames(const Ast& ast, std::unordered_set<std::string_view>& outNames)
    {
        Ast::visit(ast, ast.root(), [&](AstNodeRef, const AstNode& node) {
            const auto* attributes = node.safeCast<AstAttributeList>();
            if (!attributes || attributes->nodeBodyRef.isInvalid() || !ast.hasNode(attributes->nodeBodyRef))
                return Ast::VisitResult::Continue;

            const auto* decl = ast.node(attributes->nodeBodyRef).safeCast<AstFunctionDecl>();
            if (!decl || decl->tokNameRef.isInvalid())
                return Ast::VisitResult::Continue;

            const size_t count = ast.spanSize(attributes->spanChildrenRef);
            for (size_t i = 0; i < count; ++i)
            {
                const AstNodeRef attributeRef = ast.nthNode(attributes->spanChildrenRef, i);
                if (attributeRef.isInvalid() || !ast.hasNode(attributeRef))
                    continue;
                const auto* attribute = ast.node(attributeRef).safeCast<AstAttribute>();
                if (!attribute)
                    continue;

                const std::string_view attributeName = autoInlineCallName(ast, attribute->nodeCallRef);
                if (attributeName == "Macro" || attributeName == "Mixin")
                {
                    outNames.insert(ast.srcView().tokenString(decl->tokNameRef));
                    break;
                }
            }
            return Ast::VisitResult::Continue;
        });
    }
}

void Parser::finalizeAutoInlineCandidates(const std::span<Ast* const> moduleAsts)
{
    std::unordered_set<std::string_view> metaFunctionNames;
    for (const Ast* ast : moduleAsts)
    {
        if (ast && ast->root().isValid())
            collectMetaFunctionNames(*ast, metaFunctionNames);
    }

    std::unordered_map<std::string_view, uint32_t>                         callCounts;
    std::unordered_map<std::string_view, uint32_t>                         useCounts;
    std::unordered_map<const Ast*, AutoInlineCallGraph>                    callGraphs;
    std::unordered_map<const Ast*, std::unordered_set<std::string_view>> unsupportedFunctionNames;
    for (const Ast* ast : moduleAsts)
    {
        if (!ast || ast->root().isInvalid())
            continue;

        Ast::visit(*ast, ast->root(), [&](AstNodeRef, const AstNode& node) {
            if (const auto* decl = node.safeCast<AstFunctionDecl>())
            {
                callGraphs[ast].addFunction(*ast, *decl);
                if (decl->autoInlineCost == UINT32_MAX && decl->tokNameRef.isValid())
                    unsupportedFunctionNames[ast].insert(ast->srcView().tokenString(decl->tokNameRef));
            }

            if (node.is(AstNodeId::Identifier))
                useCounts[ast->srcView().tokenString(node.tokRef())]++;

            const auto* call = node.safeCast<AstCallExpr>();
            if (!call)
                return Ast::VisitResult::Continue;

            const std::string_view name = autoInlineCallName(*ast, call->nodeExprRef);
            if (!name.empty())
                callCounts[name]++;
            return Ast::VisitResult::Continue;
        });
    }

    // Auto-inlining waits for the callee's resolved body before cloning it. A cycle of candidates
    // would therefore turn a legal recursive call graph into a sema wait cycle. Detect it from the
    // immutable parsed graph and leave every member out of line. Cross-Ast calls cannot auto-inline,
    // so each Ast has its own graph; keeping unrelated names apart also avoids false cycles.
    for (auto& [_, callGraph] : callGraphs)
        callGraph.findCycles();

    for (Ast* ast : moduleAsts)
    {
        if (!ast || ast->root().isInvalid())
            continue;

        Ast::visit(*ast, ast->root(), [&](AstNodeRef nodeRef, const AstNode& node) {
            const auto* decl = node.safeCast<AstFunctionDecl>();
            if (!decl || decl->autoInlineCost > K_AUTO_INLINE_LAST_CALL_COST || decl->tokNameRef.isInvalid())
                return Ast::VisitResult::Continue;

            const std::string_view name        = ast->srcView().tokenString(decl->tokNameRef);
            auto*                  mutableDecl = ast->node<AstNodeId::FunctionDecl>(nodeRef);
            const bool             bodyHasCall = decl->hasFlag(AstFunctionFlagsE::AutoInlineHasCalls);
            const auto callGraphIt = callGraphs.find(ast);
            if (bodyHasCall && callGraphIt != callGraphs.end() && callGraphIt->second.callsAny(name, metaFunctionNames))
                return Ast::VisitResult::Continue;
            const auto unsupportedIt = unsupportedFunctionNames.find(ast);
            // Re-sema of an inlined wrapper can itself expand an explicitly-inline callee. If that
            // callee owns a closure, local function, error-management scope, or another construct
            // the parser already rejected, moving the wrapper merely hides the same unsupported
            // materialization one call deeper.
            if (bodyHasCall && callGraphIt != callGraphs.end() && unsupportedIt != unsupportedFunctionNames.end() &&
                callGraphIt->second.callsAny(name, unsupportedIt->second))
                return Ast::VisitResult::Continue;
            if (callGraphIt != callGraphs.end() && callGraphIt->second.isCyclic(name) && bodyHasCall)
            {
                mutableDecl->flags().remove(AstFunctionFlagsE::AutoInlineBody);
                return Ast::VisitResult::Continue;
            }

            const auto it = callCounts.find(name);
            const auto useIt = useCounts.find(name);
            const bool hasLastCallBonus = it != callCounts.end() && it->second == 1 &&
                                          useIt != useCounts.end() && useIt->second == 1;
            if ((!bodyHasCall && decl->autoInlineCost <= K_AUTO_INLINE_MAX_BODY_TOKENS) || hasLastCallBonus)
                mutableDecl->addFlag(AstFunctionFlagsE::AutoInlineBody);
            return Ast::VisitResult::Continue;
        });
    }
}

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

    // Generated snippets are parsed without an explicit enclosing token pair. Stop
    // on EOF or on a recovered closing delimiter that belongs to the caller.
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
    ctx_ = &ctx;
    ast_ = &ast;

    // Generated parsing temporarily swaps the owner AST source view so token/code
    // locations are wired to the generated snippet. That state lives on the shared
    // AST, so concurrent #ast parses for the same source file must serialize here.
    const std::scoped_lock generatedParseLock(ast_->generatedParseMutex());

    firstToken_                     = &srcView.tokens().front();
    lastToken_                      = &srcView.tokens().back();
    curToken_                       = startTokRef.isValid() ? &srcView.tokens()[startTokRef.get()] : firstToken_;
    depthParen_                     = 0;
    depthBracket_                   = 0;
    depthCurly_                     = 0;
    lastErrorToken_                 = TokenRef::invalid();
    fwdPassMode_                    = FwdParseMode::Copy;
    fwdCurMode_                     = FwdParseMode::Copy;
    fwdDeclActive_                  = false;
    fwdSeenParam_                   = false;
    fwdStmtTrigger_                 = false;
    fwdReparseDepth_                = 0;
    closureCaptureStopDepthParen_   = 0xFFFFFFFFu;
    closureCaptureStopDepthBracket_ = 0xFFFFFFFFu;
    closureCaptureStopDepthCurly_   = 0xFFFFFFFFu;

    SourceView*      previousSrcView = Ast::setThreadSourceViewOverride(&srcView);
    const AstNodeRef result          = parseGeneratedContent(mode);
    finalizeGeneratedAutoInlineCandidates(*ast_, result);
    Ast::setThreadSourceViewOverride(previousSrcView);

    return result;
}

void Parser::setReportArguments(Diagnostic& diag, TokenRef tokRef) const
{
    const Token& token = ast_->srcView().token(tokRef);

    // Parser diagnostics include neighboring token families so messages can explain
    // both what was seen and the local context without re-walking the token stream.
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

    // A stray closing delimiter is usually clearer as "no matching opening" than as
    // a generic unexpected-token error. Depth counters tell whether we are inside a
    // matching construct at the current recovery point.
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

    if (tknRef == lastErrorToken_ || fwdReparseDepth_ > 0)
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

        if (tknRef == lastErrorToken_ || fwdReparseDepth_ > 0)
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

    if (tknRef == lastErrorToken_ || fwdReparseDepth_ > 0)
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
    // Trailing code literal of the preceding call: 'call(args) #code(a, b) { ... }'
    if (is(TokenId::CompilerCode))
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
    ctx_ = &ctx;
    ast_ = &ast;

    firstToken_                     = &ast_->srcView().tokens().front();
    lastToken_                      = &ast_->srcView().tokens().back();
    curToken_                       = firstToken_;
    closureCaptureStopDepthParen_   = 0xFFFFFFFFu;
    closureCaptureStopDepthBracket_ = 0xFFFFFFFFu;
    closureCaptureStopDepthCurly_   = 0xFFFFFFFFu;

    // Force the first node to be invalid, so that AstNodeRef 0 is invalid
    (void) ast_->makeNode<AstNodeId::Invalid>(TokenRef::invalid());

    ast_->setRoot(parseFile());
    ast_->captureParsedNodeBoundary();
}

SWC_END_NAMESPACE();
