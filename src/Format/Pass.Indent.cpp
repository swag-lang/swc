#include "pch.h"
#include "Format/FormatPassUtil.h"
#include "Format/FormatPasses.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::PieceColumn;

    struct OpenBracket
    {
        uint32_t piece         = FormatPiece::INVALID_INDEX;
        uint32_t column        = 0;
        uint32_t itemColumn    = UINT32_MAX; // item carried on the bracket's own line, if any
        uint32_t operandColumn = UINT32_MAX; // where the bracket's content starts, taken from the first wrapped line when needed
    };

    // Where a continuation line landed, and what it was measured from. A line
    // with no anchor keeps a relative or canonical indent and owes nothing to
    // any other piece.
    struct ContinuationAnchor
    {
        uint32_t columns     = 0;
        uint32_t piece       = FormatPiece::INVALID_INDEX;
        uint32_t pieceColumn = 0;
    };

    bool isStatementLine(const FormatPiece& piece)
    {
        // Literal braces (array / struct literals) are NOT statement
        // starts: their lines keep their relative indentation.
        return piece.roles.hasAny({FormatRoleE::StmtStart, FormatRoleE::CaseLabel, FormatRoleE::AttrOpen,
                                   FormatRoleE::ElseKeyword, FormatRoleE::EnumValueStart, FormatRoleE::FieldDeclStart,
                                   FormatRoleE::BlockOpen, FormatRoleE::BlockClose, FormatRoleE::DestructuringClose,
                                   FormatRoleE::WhereKeyword});
    }

    class IndentPass
    {
    public:
        explicit IndentPass(FormatModel& model) :
            model_(&model),
            options_(&model.options())
        {
        }

        void run()
        {
            if (options_->indentStyle == FormatIndentStyle::Preserve)
                return;

            sortedBlocks_ = model_->blocks();
            std::ranges::sort(sortedBlocks_, [](const FormatBlock& a, const FormatBlock& b) { return a.openPiece < b.openPiece; });
            sortedInlineBodies_ = model_->inlineBodies();
            std::ranges::sort(sortedInlineBodies_, [](const FormatInlineBody& a, const FormatInlineBody& b) { return a.doPiece < b.doPiece; });

            std::vector<uint32_t> lineStarts;
            model_->collectLineStarts(lineStarts);

            for (const uint32_t lineStart : lineStarts)
                processLine(lineStart);
            flushComments(lastCodeCols_, true);
        }

    private:
        uint32_t blockContribution(const FormatBlock& block) const
        {
            // A `where { ... }` block is itself indented one level under its
            // declaration: its content sits two levels deep.
            if (model_->piece(block.headPiece).hasRole(FormatRoleE::WhereKeyword))
                return 2;

            switch (block.kind)
            {
                case FormatBlockKind::Namespace:
                    return options_->indentNamespaceBody.value_or(true) ? 1 : 0;
                case FormatBlockKind::Impl:
                    return options_->indentImplBody.value_or(true) ? 1 : 0;
                case FormatBlockKind::Struct:
                    return options_->indentStructBody.value_or(true) ? 1 : 0;
                case FormatBlockKind::Enum:
                    return options_->indentEnumBody.value_or(true) ? 1 : 0;
                case FormatBlockKind::Switch:
                    return 0; // handled per line (case labels vs case bodies)
                case FormatBlockKind::Interface:
                case FormatBlockKind::Function:
                case FormatBlockKind::Control:
                case FormatBlockKind::Plain:
                    return 1;
            }
            return 1;
        }

        void updateStacks(const uint32_t lineStart)
        {
            while (nextBlock_ < sortedBlocks_.size() && sortedBlocks_[nextBlock_].openPiece < lineStart)
                blockStack_.push_back({sortedBlocks_[nextBlock_++], false});
            while (!blockStack_.empty() && blockStack_.back().block.closePiece < lineStart)
                blockStack_.pop_back();

            while (nextInlineBody_ < sortedInlineBodies_.size() && sortedInlineBodies_[nextInlineBody_].doPiece < lineStart)
                inlineBodyStack_.push_back(sortedInlineBodies_[nextInlineBody_++]);
            while (!inlineBodyStack_.empty() && inlineBodyStack_.back().lastPiece < lineStart)
                inlineBodyStack_.pop_back();
        }

        // `where` clauses and the braces of their block bodies sit
        // one level under the declaration they constrain.
        bool lineBelongsToWhereClause(const uint32_t lineStart, const FormatPiece& piece) const
        {
            if (piece.hasRole(FormatRoleE::WhereKeyword))
                return true;
            if (!piece.roles.hasAny({FormatRoleE::BlockOpen, FormatRoleE::BlockClose}))
                return false;
            for (const FormatBlock& block : model_->blocks())
            {
                if (block.openPiece == lineStart || block.closePiece == lineStart)
                    return model_->piece(block.headPiece).hasRole(FormatRoleE::WhereKeyword);
            }
            return false;
        }

        void processLine(const uint32_t lineStart)
        {
            updateStacks(lineStart);

            const FormatPiece& piece = model_->piece(lineStart);
            if (piece.removed)
                return;

            const bool editable = FormatPassUtil::canEditGap(*model_, lineStart) && lineStart != 0 &&
                                  model_->gapHasNewline(lineStart);

            // A whole-line comment introduces the code line under it, so it
            // takes that line's indentation. A closing brace is the exception:
            // it sits one level out, and a comment cannot introduce it, so the
            // comment stays where its own block puts it.
            if (piece.isComment && FormatPassUtil::lineEndOf(*model_, lineStart) == lineStart)
            {
                if (editable)
                    pendingComments_.push_back({lineStart, statementColumns(lineStart, piece)});
                return;
            }

            const uint32_t oldCols = FormatModel::textColumns(model_->lineIndentOf(lineStart), std::max(options_->tabWidth, 1u));

            uint32_t   newCols                = 0;
            const bool isStatement            = isStatementLine(piece);
            const bool updatesStatementAnchor = isStatement && piece.isNot(TokenId::KwdElse) &&
                                                !piece.hasRole(FormatRoleE::DestructuringClose);
            if (isStatement)
            {
                newCols = statementColumns(lineStart, piece);
                if (piece.hasRole(FormatRoleE::AttrOpen) && !options_->indentAttributes.value_or(true))
                    newCols = oldCols;
                if (updatesStatementAnchor)
                {
                    lastStmtOldCols_ = oldCols;
                    lastStmtNewCols_ = newCols;
                }
            }
            else
            {
                const ContinuationAnchor anchor = continuationColumns(lineStart, oldCols);
                newCols                         = anchor.columns;

                for (const PendingComment& comment : pendingComments_)
                    recordHangingLine(comment.line, anchor);
                recordHangingLine(lineStart, anchor);

                // A bracket that ended its line takes its first continuation
                // line as the operand anchor for the rest of the expression.
                if (!parenStack_.empty() && parenStack_.back().operandColumn == UINT32_MAX)
                    parenStack_.back().operandColumn = newCols;
            }

            flushComments(newCols, isStatement && piece.hasRole(FormatRoleE::BlockClose));
            lastCodeCols_ = newCols;

            if (editable && newCols != oldCols)
                setLineIndent(lineStart, newCols);

            if (updatesStatementAnchor)
                updateStatementOperandAnchor(lineStart);
            const uint32_t lineEnd = FormatPassUtil::lineEndOf(*model_, lineStart);
            prevLineEndsBinaryOp_  = model_->piece(lineEnd).roles.hasAny({FormatRoleE::BinaryOp, FormatRoleE::TernaryOp});

            trackBrackets(lineStart);
        }

        // The first operand of a statement line: what wrapped operand lines
        // align with under `align-operands`. The operand starts after a
        // leading control keyword, or after the assignment operator when the
        // line has one. The piece is kept too, so the alignment pass can move
        // those wrapped lines again if it later shifts this one.
        void updateStatementOperandAnchor(const uint32_t lineStart)
        {
            lastStmtOperandCol_   = UINT32_MAX;
            lastStmtOperandPiece_ = FormatPiece::INVALID_INDEX;
            lastStmtIsCaseLabel_  = model_->piece(lineStart).hasRole(FormatRoleE::CaseLabel);

            std::vector<PieceColumn> columns;
            FormatPassUtil::computeLineColumns(*model_, lineStart, &columns);
            if (columns.empty())
                return;

            const auto take = [&](const size_t index) {
                if (index >= columns.size())
                    return;
                lastStmtOperandCol_   = columns[index].column;
                lastStmtOperandPiece_ = columns[index].piece;
            };

            // A `case` line's first value is what the rest of the value list
            // lines up under, exactly like the first argument of a call.
            if (lastStmtIsCaseLabel_)
            {
                take(1);
                return;
            }

            for (size_t c = 0; c < columns.size(); ++c)
            {
                const FormatPiece& piece = model_->piece(columns[c].piece);
                if (piece.roles.hasAny({FormatRoleE::AssignOp, FormatRoleE::InitAssign}))
                {
                    lastStmtOperandCol_   = UINT32_MAX;
                    lastStmtOperandPiece_ = FormatPiece::INVALID_INDEX;
                    take(c + 1);
                    return;
                }
                if (c == 0)
                    take(piece.hasRole(FormatRoleE::ControlKeyword) ? 1 : 0);
            }
        }

        uint32_t statementColumns(const uint32_t lineStart, const FormatPiece& piece)
        {
            const uint32_t indentWidth = std::max(options_->indentWidth, 1u);

            uint32_t depth = 0;
            for (const StackEntry& entry : blockStack_)
            {
                const FormatBlock& block = entry.block;
                if (block.closePiece == lineStart)
                    continue; // the closing line sits at the parent level

                if (block.kind == FormatBlockKind::Switch)
                {
                    // A line is a label of THIS switch when its depth matches
                    // the switch's inner bracket depth.
                    const bool ownLabel = piece.hasRole(FormatRoleE::CaseLabel) &&
                                          piece.depth == model_->piece(block.openPiece).depth + 1;
                    depth += options_->indentCaseLabels.value_or(true) ? 1 : 0;
                    if (entry.sawCase && !ownLabel && options_->indentCaseBlocks.value_or(true))
                        depth += 1;
                    continue;
                }

                depth += blockContribution(block);
            }

            depth += static_cast<uint32_t>(inlineBodyStack_.size());

            // A case label opens the body region of its owning switch.
            if (piece.hasRole(FormatRoleE::CaseLabel))
            {
                for (StackEntry& entry : blockStack_)
                {
                    if (entry.block.kind == FormatBlockKind::Switch &&
                        piece.depth == model_->piece(entry.block.openPiece).depth + 1)
                        entry.sawCase = true;
                }
            }

            if (lineBelongsToWhereClause(lineStart, piece))
                depth += 1;

            return depth * indentWidth;
        }

        ContinuationAnchor continuationColumns(const uint32_t lineStart, const uint32_t oldCols) const
        {
            // Wrapped lines sit under the item the bracket carries on its own
            // line. A bracket that ends its line has nothing to align with:
            // its content falls through to the canonical / relative indent
            // below, which is what keeps hand-packed data tables intact.
            if (options_->alignAfterOpenBracket.value_or(false) && !parenStack_.empty() &&
                parenStack_.back().itemColumn != UINT32_MAX)
            {
                const OpenBracket& bracket = parenStack_.back();
                return {bracket.itemColumn, bracket.piece, bracket.column};
            }

            // Operand lines of a wrapped binary expression align with the first
            // operand of the expression they continue: the bracket's own first
            // item when the expression is nested in one, the statement's first
            // operand otherwise. Anchoring a nested operand on the statement
            // would tear it out of the argument list it belongs to.
            if (options_->alignOperands.value_or(false) &&
                (prevLineEndsBinaryOp_ || model_->piece(lineStart).roles.hasAny({FormatRoleE::BinaryOp, FormatRoleE::TernaryOp})))
            {
                if (!parenStack_.empty())
                {
                    const OpenBracket& bracket = parenStack_.back();
                    if (bracket.operandColumn != UINT32_MAX)
                        return {bracket.operandColumn, bracket.piece, bracket.column};
                }
                else if (lastStmtOperandCol_ != UINT32_MAX)
                    return {lastStmtOperandCol_, lastStmtOperandPiece_, lastStmtOperandCol_};
            }

            // Inside brackets, force the canonical continuation indent instead
            // of keeping the relative one: one level per open bracket, so a row
            // of a table nested two brackets deep lands two levels in rather
            // than being flattened onto the statement's first continuation.
            if (options_->indentInsideParens.value_or(false) && !parenStack_.empty())
                return {lastStmtNewCols_ + static_cast<uint32_t>(parenStack_.size()) * std::max(options_->continuationIndentWidth, 1u)};

            // A wrapped `case` value list has no bracket to hang from: its
            // continuations take the column of the first value.
            if (lastStmtIsCaseLabel_ && parenStack_.empty() && lastStmtOperandCol_ != UINT32_MAX)
                return {lastStmtOperandCol_, lastStmtOperandPiece_, lastStmtOperandCol_};

            // Outside every bracket there is no hand-packed table to protect, so
            // the continuation takes the canonical indent and a mangled one gets
            // repaired. Inside a bracket the source distance to the statement is
            // kept: that is what holds a data table's columns together.
            const int32_t relative = static_cast<int32_t>(oldCols) - static_cast<int32_t>(lastStmtOldCols_);
            if (relative > 0 && !parenStack_.empty())
                return {lastStmtNewCols_ + static_cast<uint32_t>(relative)};

            return {lastStmtNewCols_ + std::max(options_->continuationIndentWidth, 1u)};
        }

        void flushComments(const uint32_t cols, const bool endsItsBlock)
        {
            for (const PendingComment& comment : pendingComments_)
            {
                const uint32_t cmtCols = endsItsBlock ? comment.ownCols : cols;
                const uint32_t oldCols = FormatModel::textColumns(model_->lineIndentOf(comment.line), std::max(options_->tabWidth, 1u));
                if (oldCols != cmtCols)
                    setLineIndent(comment.line, cmtCols);
            }
            pendingComments_.clear();
        }

        void setLineIndent(const uint32_t lineStart, const uint32_t cols) const
        {
            const uint32_t newlines = model_->gapNewlineCount(lineStart);
            if (newlines == 0)
                return;
            model_->setGapBreak(lineStart, newlines, FormatPassUtil::indentForColumns(*model_, cols).view());
        }

        void trackBrackets(const uint32_t lineStart)
        {
            std::vector<PieceColumn> columns;
            FormatPassUtil::computeLineColumns(*model_, lineStart, &columns);

            for (size_t c = 0; c < columns.size(); ++c)
            {
                const FormatPiece& piece = model_->piece(columns[c].piece);
                // Literal braces carry wrapped items exactly like a call paren
                // does; block braces open a body and are indented, not aligned.
                if (piece.is(TokenId::SymLeftParen) || piece.is(TokenId::SymLeftBracket) || piece.hasRole(FormatRoleE::LiteralOpen))
                {
                    // An item on the bracket's own line anchors everything
                    // wrapped inside it; a bracket that ends its line has none
                    // yet and takes the first continuation line instead.
                    const uint32_t item = c + 1 < columns.size() ? columns[c + 1].column : UINT32_MAX;
                    parenStack_.push_back({columns[c].piece, columns[c].column, item, item});
                }
                else if (piece.is(TokenId::SymRightParen) || piece.is(TokenId::SymRightBracket) || piece.hasRole(FormatRoleE::LiteralClose))
                {
                    if (!parenStack_.empty())
                        parenStack_.pop_back();
                }
            }
        }

        // Remembers a continuation line that was measured from another piece,
        // so the alignment pass can move it along when it shifts the line that
        // piece belongs to.
        void recordHangingLine(const uint32_t lineStart, const ContinuationAnchor& anchor) const
        {
            if (anchor.piece == FormatPiece::INVALID_INDEX || anchor.columns < anchor.pieceColumn)
                return;
            model_->hangingLines().push_back({lineStart, anchor.piece, anchor.columns - anchor.pieceColumn});
        }

        struct StackEntry
        {
            FormatBlock block;
            bool        sawCase = false;
        };

        // A whole-line comment, with the column it takes as content of the
        // block that encloses it.
        struct PendingComment
        {
            uint32_t line;
            uint32_t ownCols;
        };

        FormatModel*                  model_;
        const FormatOptions*          options_;
        std::vector<FormatBlock>      sortedBlocks_;
        std::vector<StackEntry>       blockStack_;
        std::vector<FormatInlineBody> sortedInlineBodies_;
        std::vector<FormatInlineBody> inlineBodyStack_;
        std::vector<OpenBracket>      parenStack_;
        std::vector<PendingComment>   pendingComments_;
        size_t                        nextBlock_            = 0;
        size_t                        nextInlineBody_       = 0;
        uint32_t                      lastStmtOldCols_      = 0;
        uint32_t                      lastStmtNewCols_      = 0;
        uint32_t                      lastCodeCols_         = 0;
        uint32_t                      lastStmtOperandCol_   = UINT32_MAX;
        uint32_t                      lastStmtOperandPiece_ = FormatPiece::INVALID_INDEX;
        bool                          prevLineEndsBinaryOp_ = false;
        bool                          lastStmtIsCaseLabel_  = false;
    };
}

namespace FormatPass
{
    void indent(FormatModel& model)
    {
        IndentPass(model).run();
    }
}

SWC_END_NAMESPACE();
