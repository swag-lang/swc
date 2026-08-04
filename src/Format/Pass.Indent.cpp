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
            flushComments(lastCodeCols_);
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

            // Whole-line comments adopt the indentation of the next code line.
            if (piece.isComment && FormatPassUtil::lineEndOf(*model_, lineStart) == lineStart)
            {
                if (editable)
                    pendingComments_.push_back(lineStart);
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
                newCols = continuationColumns(lineStart, oldCols);
            }

            if (!isStatement)
            {
                for (const uint32_t commentLine : pendingComments_)
                    recordHangingLine(commentLine, newCols);
                recordHangingLine(lineStart, newCols);

                // A bracket that ended its line takes its first continuation
                // line as the operand anchor for the rest of the expression.
                if (!parenStack_.empty() && parenStack_.back().operandColumn == UINT32_MAX)
                    parenStack_.back().operandColumn = newCols;
            }

            flushComments(newCols);
            lastCodeCols_ = newCols;

            if (editable && newCols != oldCols)
                setLineIndent(lineStart, newCols);

            if (updatesStatementAnchor)
                lastStmtOperandCol_ = operandAnchorColumn(lineStart);
            const uint32_t lineEnd = FormatPassUtil::lineEndOf(*model_, lineStart);
            prevLineEndsBinaryOp_  = model_->piece(lineEnd).roles.hasAny({FormatRoleE::BinaryOp, FormatRoleE::TernaryOp});

            trackBrackets(lineStart);
        }

        // Column of the first operand of a statement line: what wrapped
        // operand lines align with under `align-operands`. The operand starts
        // after a leading control keyword, or after the assignment operator
        // when the line has one.
        uint32_t operandAnchorColumn(const uint32_t lineStart) const
        {
            std::vector<PieceColumn> columns;
            FormatPassUtil::computeLineColumns(*model_, lineStart, &columns);
            if (columns.empty())
                return UINT32_MAX;

            uint32_t anchor = UINT32_MAX;
            for (size_t c = 0; c < columns.size(); ++c)
            {
                const FormatPiece& piece = model_->piece(columns[c].piece);
                if (piece.roles.hasAny({FormatRoleE::AssignOp, FormatRoleE::InitAssign}))
                    return c + 1 < columns.size() ? columns[c + 1].column : UINT32_MAX;
                if (c == 0 && piece.hasRole(FormatRoleE::ControlKeyword))
                    anchor = columns.size() > 1 ? columns[1].column : UINT32_MAX;
                else if (c == 0)
                    anchor = columns[0].column;
            }
            return anchor;
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

        uint32_t continuationColumns(const uint32_t lineStart, const uint32_t oldCols) const
        {
            // Wrapped lines sit under the item the bracket carries on its own
            // line. A bracket that ends its line has nothing to align with:
            // its content falls through to the canonical / relative indent
            // below, which is what keeps hand-packed data tables intact.
            if (options_->alignAfterOpenBracket.value_or(false) && !parenStack_.empty() &&
                parenStack_.back().itemColumn != UINT32_MAX)
                return parenStack_.back().itemColumn;

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
                    if (parenStack_.back().operandColumn != UINT32_MAX)
                        return parenStack_.back().operandColumn;
                }
                else if (lastStmtOperandCol_ != UINT32_MAX)
                    return lastStmtOperandCol_;
            }

            // Inside brackets, force the canonical continuation indent instead
            // of keeping the relative one.
            if (options_->indentInsideParens.value_or(false) && !parenStack_.empty())
                return lastStmtNewCols_ + std::max(options_->continuationIndentWidth, 1u);

            const int32_t relative = static_cast<int32_t>(oldCols) - static_cast<int32_t>(lastStmtOldCols_);
            if (relative > 0)
                return lastStmtNewCols_ + static_cast<uint32_t>(relative);

            return lastStmtNewCols_ + std::max(options_->continuationIndentWidth, 1u);
        }

        void flushComments(const uint32_t cols)
        {
            for (const uint32_t commentLine : pendingComments_)
            {
                const uint32_t oldCols = FormatModel::textColumns(model_->lineIndentOf(commentLine), std::max(options_->tabWidth, 1u));
                if (oldCols != cols)
                    setLineIndent(commentLine, cols);
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

        // Remembers a continuation line that visually hangs inside the bracket
        // it sits in, so the alignment pass can move it along when it shifts
        // the line the bracket belongs to.
        void recordHangingLine(const uint32_t lineStart, const uint32_t cols)
        {
            if (parenStack_.empty())
                return;
            const OpenBracket& bracket = parenStack_.back();
            if (bracket.piece == FormatPiece::INVALID_INDEX || cols <= bracket.column)
                return; // block bodies and data-table rows sit left of their bracket
            model_->hangingLines().push_back({lineStart, bracket.piece, cols - bracket.column});
        }

        struct StackEntry
        {
            FormatBlock block;
            bool        sawCase = false;
        };

        FormatModel*                  model_;
        const FormatOptions*          options_;
        std::vector<FormatBlock>      sortedBlocks_;
        std::vector<StackEntry>       blockStack_;
        std::vector<FormatInlineBody> sortedInlineBodies_;
        std::vector<FormatInlineBody> inlineBodyStack_;
        std::vector<OpenBracket>      parenStack_;
        std::vector<uint32_t>         pendingComments_;
        size_t                        nextBlock_            = 0;
        size_t                        nextInlineBody_       = 0;
        uint32_t                      lastStmtOldCols_      = 0;
        uint32_t                      lastStmtNewCols_      = 0;
        uint32_t                      lastCodeCols_         = 0;
        uint32_t                      lastStmtOperandCol_   = UINT32_MAX;
        bool                          prevLineEndsBinaryOp_ = false;
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
