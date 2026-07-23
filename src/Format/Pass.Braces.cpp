#include "pch.h"
#include "Format/FormatPasses.h"
#include "Format/FormatPassUtil.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;

    bool rangeEditable(const FormatModel& model, const uint32_t first, const uint32_t last)
    {
        for (uint32_t i = first; i <= last && i < model.numPieces(); ++i)
        {
            if (model.piece(i).frozen || model.gapBefore(i).frozen)
                return false;
        }
        return true;
    }

    bool blockIsSingleLine(const FormatModel& model, const FormatBlock& block)
    {
        for (uint32_t i = block.openPiece + 1; i <= block.closePiece; ++i)
        {
            if (model.piece(i).removed)
                continue;
            if (model.gapHasNewline(i))
                return false;
        }
        return true;
    }

    bool blockIsEmpty(const FormatModel& model, const FormatBlock& block)
    {
        return model.nextPiece(block.openPiece) == block.closePiece;
    }

    uint32_t blockStatementCount(const FormatModel& model, const FormatBlock& block)
    {
        const uint32_t innerDepth = model.piece(block.openPiece).depth + 1;
        uint32_t       count      = 0;
        for (uint32_t i = block.openPiece + 1; i < block.closePiece; ++i)
        {
            const FormatPiece& piece = model.piece(i);
            if (piece.removed)
                continue;
            if (piece.depth == innerDepth && piece.roles.hasAny({FormatRoleE::StmtStart, FormatRoleE::CaseLabel}))
                count++;
        }
        return count;
    }

    bool blockHasComment(const FormatModel& model, const FormatBlock& block)
    {
        for (uint32_t i = block.openPiece + 1; i < block.closePiece; ++i)
        {
            if (!model.piece(i).removed && model.piece(i).isComment)
                return true;
        }
        return false;
    }

    bool blockHasNestedBraces(const FormatModel& model, const FormatBlock& block)
    {
        for (uint32_t i = block.openPiece + 1; i < block.closePiece; ++i)
        {
            if (!model.piece(i).removed && model.piece(i).is(TokenId::SymLeftCurly))
                return true;
        }
        return false;
    }

    class BracesPass
    {
    public:
        explicit BracesPass(FormatModel& model) :
            model_(&model),
            options_(&model.options())
        {
        }

        void runShortBlocks()
        {
            for (const FormatBlock& block : model_->blocks())
            {
                if (!rangeEditable(*model_, block.openPiece, block.closePiece))
                    continue;

                const FormatShortBlockStyle style = shortStyleFor(block);
                if (style == FormatShortBlockStyle::Preserve)
                    continue;

                const bool singleLine = blockIsSingleLine(*model_, block);
                const bool empty      = blockIsEmpty(*model_, block);

                switch (style)
                {
                    case FormatShortBlockStyle::Never:
                        if (singleLine && !empty)
                            splitBlock(block);
                        break;

                    case FormatShortBlockStyle::Empty:
                        if (singleLine && !empty)
                            splitBlock(block);
                        break;

                    case FormatShortBlockStyle::Inline:
                    case FormatShortBlockStyle::Always:
                        if (!singleLine && !empty)
                            tryJoinBlock(block);
                        break;

                    case FormatShortBlockStyle::Preserve:
                        break;
                }
            }

            runShortCases();
        }

        void runBraces()
        {
            for (const FormatBlock& block : model_->blocks())
            {
                if (!rangeEditable(*model_, block.openPiece, block.closePiece))
                    continue;

                const bool empty = blockIsEmpty(*model_, block);
                if (empty && options_->compactEmptyBraces)
                {
                    applyCompactEmpty(block, *options_->compactEmptyBraces);
                    continue;
                }

                if (blockIsSingleLine(*model_, block))
                    continue;

                applyBraceStyle(block);
                splitBraceAdjacentContent(block);
            }

            applyBreakBeforeElse();
            applyBreakBeforeWhere();
        }

    private:
        FormatShortBlockStyle shortStyleFor(const FormatBlock& block) const
        {
            // Blocks embedded in an expression or a type keep their layout,
            // except closure bodies which have their own dedicated option.
            if (block.exprLevel)
            {
                if (block.kind == FormatBlockKind::Function)
                    return options_->allowShortClosuresOnSingleLine;
                return FormatShortBlockStyle::Preserve;
            }

            switch (block.kind)
            {
                case FormatBlockKind::Function:
                    return options_->allowShortFunctionsOnSingleLine;
                case FormatBlockKind::Struct:
                    return options_->allowShortStructsOnSingleLine;
                case FormatBlockKind::Enum:
                    return options_->allowShortEnumsOnSingleLine;

                case FormatBlockKind::Control:
                case FormatBlockKind::Plain:
                {
                    FormatShortBlockStyle style = options_->allowShortBlocksOnSingleLine;
                    const FormatPiece&    head  = model_->piece(block.headPiece);
                    if (head.is(TokenId::KwdIf) || head.is(TokenId::KwdElseIf) || head.is(TokenId::KwdElse))
                    {
                        if (options_->allowShortIfStatementsOnSingleLine)
                            style = *options_->allowShortIfStatementsOnSingleLine ? FormatShortBlockStyle::Inline : FormatShortBlockStyle::Never;
                    }
                    else if (head.is(TokenId::KwdWhile) || head.is(TokenId::KwdFor))
                    {
                        if (options_->allowShortLoopsOnSingleLine)
                            style = *options_->allowShortLoopsOnSingleLine ? FormatShortBlockStyle::Inline : FormatShortBlockStyle::Never;
                    }
                    return style;
                }

                case FormatBlockKind::Interface:
                case FormatBlockKind::Namespace:
                case FormatBlockKind::Impl:
                case FormatBlockKind::Switch:
                    return FormatShortBlockStyle::Preserve;
            }

            return FormatShortBlockStyle::Preserve;
        }

        void splitBlock(const FormatBlock& block) const
        {
            const Utf8 base(model_->lineIndentOf(block.headPiece));
            const Utf8 inner = FormatPassUtil::indentPlusOne(*model_, base.view());

            const uint32_t innerDepth = model_->piece(block.openPiece).depth + 1;
            bool           first      = true;
            for (uint32_t i = block.openPiece + 1; i < block.closePiece; ++i)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.removed)
                    continue;

                const bool isStmt = piece.depth == innerDepth && piece.roles.hasAny({FormatRoleE::StmtStart, FormatRoleE::CaseLabel});
                if (first || isStmt)
                    model_->setGapBreak(i, 1, inner.view());
                first = false;
            }

            model_->setGapBreak(block.closePiece, 1, base.view());
        }

        void tryJoinBlock(const FormatBlock& block) const
        {
            if (blockStatementCount(*model_, block) > 1)
                return;
            if (blockHasComment(*model_, block) || blockHasNestedBraces(*model_, block))
                return;

            const uint32_t firstContent = model_->nextPiece(block.openPiece);
            SWC_ASSERT(firstContent != INVALID_PIECE && firstContent != block.closePiece);

            // The single statement must not span several lines itself.
            for (uint32_t i = firstContent + 1; i < block.closePiece; ++i)
            {
                if (!model_->piece(i).removed && model_->gapHasNewline(i))
                    return;
            }

            if (options_->columnLimit > 0)
            {
                const uint32_t headStart = model_->lineStartOf(block.headPiece);
                uint32_t       width     = FormatPassUtil::lineWidth(*model_, headStart);
                for (uint32_t i = firstContent; i < block.closePiece; ++i)
                {
                    if (model_->piece(i).removed)
                        continue;
                    width += FormatModel::textColumns(model_->piece(i).text, std::max(options_->tabWidth, 1u));
                    width += i == firstContent ? 1 : model_->gapColumns(i);
                }
                width += 2; // " }"
                if (width > options_->columnLimit)
                    return;
            }

            if (model_->gapHasNewline(block.openPiece) && block.openPiece != block.headPiece)
            {
                const uint32_t prev = model_->prevPiece(block.openPiece);
                if (prev == INVALID_PIECE || model_->piece(prev).isComment)
                    return;
                model_->setGapSpaces(block.openPiece, 1);
            }
            model_->setGapSpaces(firstContent, 1);
            model_->setGapSpaces(block.closePiece, 1);
        }

        void applyCompactEmpty(const FormatBlock& block, const bool compact) const
        {
            if (!compact)
                return;
            if (model_->gapHasNewline(block.closePiece))
                model_->setGapSpaces(block.closePiece, 0);
            if (model_->gapHasNewline(block.openPiece) && block.openPiece != block.headPiece)
            {
                const uint32_t prev = model_->prevPiece(block.openPiece);
                if (prev != INVALID_PIECE && !model_->piece(prev).isComment)
                    model_->setGapSpaces(block.openPiece, 1);
            }
        }

        void applyBraceStyle(const FormatBlock& block) const
        {
            switch (options_->braceStyle)
            {
                case FormatBraceStyle::Attach:
                case FormatBraceStyle::Stroustrup:
                {
                    if (!model_->gapHasNewline(block.openPiece) || block.openPiece == block.headPiece)
                        break;
                    const uint32_t prev = model_->prevPiece(block.openPiece);
                    if (prev == INVALID_PIECE || model_->piece(prev).isComment)
                        break;
                    model_->setGapSpaces(block.openPiece, 1);
                    break;
                }

                case FormatBraceStyle::Allman:
                {
                    if (model_->gapHasNewline(block.openPiece) || block.openPiece == block.headPiece)
                        break;
                    model_->setGapBreak(block.openPiece, 1, model_->lineIndentOf(block.headPiece));
                    break;
                }

                case FormatBraceStyle::Preserve:
                    break;
            }
        }

        // In a multi-line block, the content must not share a line with the
        // braces: `{ stmt` and `stmt }` each get their own line.
        void splitBraceAdjacentContent(const FormatBlock& block) const
        {
            if (options_->braceStyle == FormatBraceStyle::Preserve)
                return;

            const Utf8 base(model_->lineIndentOf(block.headPiece));

            const uint32_t firstContent = model_->nextPiece(block.openPiece);
            if (firstContent != INVALID_PIECE && firstContent != block.closePiece &&
                !model_->gapHasNewline(firstContent) && !model_->piece(firstContent).isComment &&
                FormatPassUtil::canEditGap(*model_, firstContent))
            {
                model_->setGapBreak(firstContent, 1, FormatPassUtil::indentPlusOne(*model_, base.view()).view());
            }

            if (!model_->gapHasNewline(block.closePiece) && FormatPassUtil::canEditGap(*model_, block.closePiece))
                model_->setGapBreak(block.closePiece, 1, base.view());
        }

        bool closesSingleLineBlock(const uint32_t closePiece) const
        {
            for (const FormatBlock& block : model_->blocks())
            {
                if (block.closePiece == closePiece)
                    return blockIsSingleLine(*model_, block);
            }
            return false;
        }

        void applyBreakBeforeElse() const
        {
            bool breakBefore;
            if (options_->breakBeforeElse)
                breakBefore = *options_->breakBeforeElse;
            else if (options_->braceStyle == FormatBraceStyle::Allman || options_->braceStyle == FormatBraceStyle::Stroustrup)
                breakBefore = true;
            else if (options_->braceStyle == FormatBraceStyle::Attach)
                breakBefore = false;
            else
                return;

            for (uint32_t i = 0; i < model_->numPieces(); ++i)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.removed || !piece.hasRole(FormatRoleE::ElseKeyword))
                    continue;
                if (!FormatPassUtil::canEditGap(*model_, i))
                    continue;

                const uint32_t prev = model_->prevPiece(i);
                if (prev == INVALID_PIECE || model_->piece(prev).isNot(TokenId::SymRightCurly))
                    continue;

                // A chain whose branch body is a one-liner stays inline:
                // `#if X { a } #else { b }`.
                if (breakBefore && closesSingleLineBlock(prev))
                    continue;

                if (breakBefore && !model_->gapHasNewline(i))
                    model_->setGapBreak(i, 1, model_->lineIndentOf(prev));
                else if (!breakBefore && model_->gapHasNewline(i))
                    model_->setGapSpaces(i, 1);
            }
        }

        // A `where` / `verify` clause moves to its own line, one level under
        // the declaration it constrains.
        void applyBreakBeforeWhere() const
        {
            if (!options_->breakBeforeWhere)
                return;
            const bool breakBefore = *options_->breakBeforeWhere;

            for (uint32_t i = 0; i < model_->numPieces(); ++i)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.removed || !piece.hasRole(FormatRoleE::WhereKeyword))
                    continue;
                if (!FormatPassUtil::canEditGap(*model_, i))
                    continue;

                if (breakBefore && !model_->gapHasNewline(i))
                {
                    const uint32_t stmt = model_->lineStartOf(i);
                    model_->setGapBreak(i, 1, FormatPassUtil::indentPlusOne(*model_, model_->lineIndentOf(stmt)).view());
                }
                else if (!breakBefore && model_->gapHasNewline(i))
                {
                    model_->setGapSpaces(i, 1);
                }
            }
        }

        void runShortCases() const
        {
            if (!options_->allowShortCaseOnSingleLine)
                return;
            const bool allow = *options_->allowShortCaseOnSingleLine;

            for (uint32_t i = 0; i < model_->numPieces(); ++i)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.removed || !piece.hasRole(FormatRoleE::CaseColon))
                    continue;

                const uint32_t body = model_->nextPiece(i);
                if (body == INVALID_PIECE || !FormatPassUtil::canEditGap(*model_, body))
                    continue;

                const FormatPiece& bodyPiece = model_->piece(body);
                if (bodyPiece.roles.hasAny({FormatRoleE::CaseLabel}) || bodyPiece.is(TokenId::SymRightCurly))
                    continue; // empty case
                if (bodyPiece.is(TokenId::SymLeftCurly) || bodyPiece.isComment)
                    continue; // braced bodies are handled as blocks

                const uint32_t caseEnd = findCaseBodyEnd(i);
                if (caseEnd == INVALID_PIECE)
                    continue;

                if (!allow)
                {
                    if (!model_->gapHasNewline(body))
                        model_->setGapBreak(body, 1, FormatPassUtil::indentPlusOne(*model_, model_->lineIndentOf(i)).view());
                    continue;
                }

                // Join a single-statement, single-line body onto the label line.
                if (!model_->gapHasNewline(body))
                    continue;

                uint32_t stmtCount = 0;
                bool     joinable  = true;
                for (uint32_t p = body; p <= caseEnd && joinable; p = model_->nextPiece(p))
                {
                    if (p == INVALID_PIECE)
                        break;
                    const FormatPiece& cur = model_->piece(p);
                    if (cur.isComment)
                        joinable = false;
                    if (cur.roles.hasAny({FormatRoleE::StmtStart}) && cur.depth == piece.depth)
                        stmtCount++;
                    if (p != body && model_->gapHasNewline(p))
                        joinable = false;
                    if (p == caseEnd)
                        break;
                }

                if (joinable && stmtCount <= 1)
                    model_->setGapSpaces(body, 1);
            }
        }

        // Last piece of a case body: everything until the next case label or
        // the closing brace of the switch.
        uint32_t findCaseBodyEnd(const uint32_t colonPiece) const
        {
            const uint32_t depth = model_->piece(colonPiece).depth;
            uint32_t       last  = INVALID_PIECE;
            for (uint32_t p = model_->nextPiece(colonPiece); p != INVALID_PIECE; p = model_->nextPiece(p))
            {
                const FormatPiece& cur = model_->piece(p);
                if (cur.depth < depth)
                    return last;
                if (cur.depth == depth && (cur.hasRole(FormatRoleE::CaseLabel) || cur.is(TokenId::SymRightCurly)))
                    return last;
                last = p;
            }
            return last;
        }

        FormatModel*         model_;
        const FormatOptions* options_;
    };
}

namespace
{
    // `;` before an end of line is a statement separator the grammar does not
    // need; prototype terminators (marked KeepSemi) stay.
    void removeRedundantSemicolons(FormatModel& model)
    {
        if (!model.options().removeRedundantSemicolons.value_or(false))
            return;

        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            const FormatPiece& piece = model.piece(i);
            if (piece.removed || piece.frozen || piece.isNot(TokenId::SymSemiColon))
                continue;
            if (piece.hasRole(FormatRoleE::KeepSemi))
                continue;
            if (!FormatPassUtil::canEditGap(model, i))
                continue;

            const uint32_t next = model.nextPiece(i);
            if (next != INVALID_PIECE && !model.gapHasNewline(next))
                continue; // same-line successor: `;` still separates
            model.removePiece(i);
        }
    }

    // `if (cond)` → `if cond` when the parentheses wrap the entire condition.
    void removeConditionParentheses(FormatModel& model)
    {
        if (!model.options().removeConditionParentheses.value_or(false))
            return;

        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            const FormatPiece& piece = model.piece(i);
            if (piece.removed || piece.frozen || !piece.hasRole(FormatRoleE::ControlKeyword))
                continue;
            if (piece.isNot(TokenId::KwdIf) && piece.isNot(TokenId::KwdElseIf) && piece.isNot(TokenId::KwdWhile) &&
                piece.isNot(TokenId::KwdSwitch))
                continue;

            const uint32_t open = model.nextPiece(i);
            if (open == INVALID_PIECE || model.piece(open).isNot(TokenId::SymLeftParen))
                continue;
            const uint32_t close = model.piece(open).match;
            if (close == INVALID_PIECE || !rangeEditable(model, open, close))
                continue;

            // The parentheses must cover the whole condition: the body (`{`
            // or trailing `do`) follows immediately.
            const uint32_t after = model.nextPiece(close);
            if (after == INVALID_PIECE ||
                (model.piece(after).isNot(TokenId::SymLeftCurly) && model.piece(after).isNot(TokenId::KwdDo)))
                continue;

            // Keep multi-line conditions: the parentheses anchor their layout.
            bool multiLine = false;
            for (uint32_t p = open + 1; p <= close && !multiLine; ++p)
            {
                if (!model.piece(p).removed && model.gapHasNewline(p))
                    multiLine = true;
            }
            if (multiLine)
                continue;

            const uint32_t inner = model.nextPiece(open);
            if (inner == close)
                continue; // empty parens: not a removable condition

            model.removePiece(open);
            model.removePiece(close);
            model.setGapSpaces(inner, 1);
        }
    }
}

namespace FormatPass
{
    void statements(FormatModel& model)
    {
        removeConditionParentheses(model);
        removeRedundantSemicolons(model);
    }

    void shortBlocks(FormatModel& model)
    {
        BracesPass(model).runShortBlocks();
    }

    void braces(FormatModel& model)
    {
        BracesPass(model).runBraces();
    }
}

SWC_END_NAMESPACE();
