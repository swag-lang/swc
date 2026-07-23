#include "pch.h"
#include "Format/FormatPasses.h"
#include "Format/FormatPassUtil.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;
    using FormatPassUtil::PieceColumn;

    struct OpenBracket
    {
        uint32_t piece  = 0;
        uint32_t column = 0;
    };

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

            std::vector<uint32_t> lineStarts;
            model_->collectLineStarts(lineStarts);

            for (const uint32_t lineStart : lineStarts)
                processLine(lineStart);
            flushComments(lastCodeCols_);
        }

    private:
        uint32_t blockContribution(const FormatBlock& block) const
        {
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
        }

        bool isStatementLine(const FormatPiece& piece) const
        {
            // Literal braces (array / struct literals) are NOT statement
            // starts: their lines keep their relative indentation.
            return piece.roles.hasAny({FormatRoleE::StmtStart, FormatRoleE::CaseLabel, FormatRoleE::AttrOpen,
                                       FormatRoleE::ElseKeyword, FormatRoleE::EnumValueStart, FormatRoleE::FieldDeclStart,
                                       FormatRoleE::BlockOpen, FormatRoleE::BlockClose});
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

            uint32_t   newCols     = 0;
            const bool isStatement = isStatementLine(piece);
            if (isStatement)
            {
                newCols = statementColumns(lineStart, piece);
                if (piece.hasRole(FormatRoleE::AttrOpen) && !options_->indentAttributes.value_or(true))
                    newCols = oldCols;
                lastStmtOldCols_ = oldCols;
                lastStmtNewCols_ = newCols;
            }
            else
            {
                newCols = continuationColumns(lineStart, oldCols);
            }

            flushComments(newCols);
            lastCodeCols_ = newCols;

            if (editable && newCols != oldCols)
                setLineIndent(lineStart, newCols);

            if (isStatement)
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

            return depth * indentWidth;
        }

        uint32_t continuationColumns(const uint32_t lineStart, const uint32_t oldCols) const
        {
            if (options_->alignAfterOpenBracket.value_or(false) && !parenStack_.empty())
                return parenStack_.back().column + 1;

            // Operand lines of a wrapped binary expression align with the
            // first operand of the statement.
            if (options_->alignOperands.value_or(false) && lastStmtOperandCol_ != UINT32_MAX &&
                (prevLineEndsBinaryOp_ || model_->piece(lineStart).roles.hasAny({FormatRoleE::BinaryOp, FormatRoleE::TernaryOp})))
                return lastStmtOperandCol_;

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
            std::vector<FormatPassUtil::PieceColumn> columns;
            FormatPassUtil::computeLineColumns(*model_, lineStart, &columns);

            for (const auto& [pieceIndex, column] : columns)
            {
                const FormatPiece& piece = model_->piece(pieceIndex);
                if (piece.is(TokenId::SymLeftParen) || piece.is(TokenId::SymLeftBracket))
                {
                    parenStack_.push_back({pieceIndex, column});
                }
                else if (piece.is(TokenId::SymRightParen) || piece.is(TokenId::SymRightBracket))
                {
                    if (!parenStack_.empty())
                        parenStack_.pop_back();
                }
            }
        }

        struct StackEntry
        {
            FormatBlock block;
            bool        sawCase = false;
        };

        FormatModel*             model_;
        const FormatOptions*     options_;
        std::vector<FormatBlock> sortedBlocks_;
        std::vector<StackEntry>  blockStack_;
        std::vector<OpenBracket> parenStack_;
        std::vector<uint32_t>    pendingComments_;
        size_t                   nextBlock_           = 0;
        uint32_t                 lastStmtOldCols_     = 0;
        uint32_t                 lastStmtNewCols_     = 0;
        uint32_t                 lastCodeCols_        = 0;
        uint32_t                 lastStmtOperandCol_  = UINT32_MAX;
        bool                     prevLineEndsBinaryOp_ = false;
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
