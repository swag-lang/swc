#include "pch.h"
#include "Format/FormatPassUtil.h"
#include "Format/FormatPasses.h"
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

    bool blockWasSingleLine(const FormatModel& model, const FormatBlock& block)
    {
        for (uint32_t i = block.headPiece + 1; i <= block.closePiece; ++i)
        {
            if (model.gapBefore(i).origText.find_first_of("\r\n") != std::string_view::npos)
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
            if (piece.depth == innerDepth && piece.roles.hasAny({FormatRoleE::StmtStart, FormatRoleE::CaseLabel, FormatRoleE::EnumValueStart}))
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

    FormatShortBlockStyle configuredShortStyle(const FormatModel& model, const FormatBlock& block)
    {
        const FormatOptions& options = model.options();

        // Blocks embedded in an expression or a type keep their layout,
        // except closure bodies which have their own dedicated option.
        if (block.exprLevel)
        {
            if (block.kind == FormatBlockKind::Function)
                return options.allowShortClosuresOnSingleLine;
            // An anonymous struct type written on one line is held there; one the
            // author already spread over several is left as written. Normalizing
            // it into a block instead would open a brace in the middle of a type
            // and hand its members to two passes that indent them differently.
            if (block.kind == FormatBlockKind::Struct && options.allowShortStructsOnSingleLine == FormatShortBlockStyle::Source &&
                blockWasSingleLine(model, block))
                return FormatShortBlockStyle::Source;
            return FormatShortBlockStyle::Preserve;
        }

        switch (block.kind)
        {
            case FormatBlockKind::Function:
                return options.allowShortFunctionsOnSingleLine;
            case FormatBlockKind::Struct:
                return options.allowShortStructsOnSingleLine;
            case FormatBlockKind::Enum:
                return options.allowShortEnumsOnSingleLine;

            case FormatBlockKind::Control:
            case FormatBlockKind::Plain:
            {
                FormatShortBlockStyle style = options.allowShortBlocksOnSingleLine;
                const FormatPiece&    head  = model.piece(block.headPiece);
                if (head.is(TokenId::KwdIf) || head.is(TokenId::KwdElseIf) || head.is(TokenId::KwdElse))
                {
                    if (options.allowShortIfStatementsOnSingleLine)
                        style = *options.allowShortIfStatementsOnSingleLine ? FormatShortBlockStyle::Inline : FormatShortBlockStyle::Never;
                }
                else if (head.is(TokenId::KwdWhile) || head.is(TokenId::KwdFor))
                {
                    if (options.allowShortLoopsOnSingleLine)
                        style = *options.allowShortLoopsOnSingleLine ? FormatShortBlockStyle::Inline : FormatShortBlockStyle::Never;
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

    bool sourceKeepsBlockSingleLine(const FormatModel& model, const FormatBlock& block)
    {
        return configuredShortStyle(model, block) == FormatShortBlockStyle::Source && blockWasSingleLine(model, block);
    }

    bool blockKeepsMembersSingleLine(const FormatModel& model, const FormatBlock& block)
    {
        const FormatShortBlockStyle style = configuredShortStyle(model, block);
        if (style == FormatShortBlockStyle::Source)
            return blockWasSingleLine(model, block);
        return (style == FormatShortBlockStyle::Inline || style == FormatShortBlockStyle::Always) && blockIsSingleLine(model, block);
    }

    bool statementBelongsToSourceSingleLineBlock(const FormatModel& model, const uint32_t piece)
    {
        for (const FormatBlock& block : model.blocks())
        {
            if (piece > block.openPiece && piece < block.closePiece && sourceKeepsBlockSingleLine(model, block))
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

        void runShortBlocks() const
        {
            for (const FormatBlock& block : model_->blocks())
            {
                if (!rangeEditable(*model_, block.openPiece, block.closePiece))
                    continue;

                const FormatShortBlockStyle style = configuredShortStyle(*model_, block);
                if (style == FormatShortBlockStyle::Preserve)
                    continue;

                const bool singleLine = blockIsSingleLine(*model_, block);
                const bool empty      = blockIsEmpty(*model_, block);

                switch (style)
                {
                    case FormatShortBlockStyle::Source:
                        if (blockWasSingleLine(*model_, block))
                        {
                            if (!singleLine && !empty)
                                tryJoinBlock(block);
                        }
                        else if (singleLine && !empty)
                            splitBlock(block);
                        break;

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

            runInlineBodies();
            runShortCases();
        }

        void runBraces() const
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

                // A brace that belongs to an expression or a type and that has no
                // short-body option of its own keeps its shape: opening a block
                // in the middle of a type expression leaves its members to the
                // list layout and the brace layout at once, and they disagree.
                if (block.exprLevel && configuredShortStyle(*model_, block) == FormatShortBlockStyle::Preserve)
                    continue;

                applyBraceStyle(block);
                splitBraceAdjacentContent(block);
            }

            applyBreakBeforeElse();
            applyBreakBeforeWhere();
        }

    private:
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

                const bool isStmt = piece.depth == innerDepth && piece.roles.hasAny({FormatRoleE::StmtStart, FormatRoleE::CaseLabel, FormatRoleE::EnumValueStart});
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

        void runInlineBodies() const
        {
            for (const FormatInlineBody& body : model_->inlineBodies())
            {
                const FormatPiece&         head   = model_->piece(body.headPiece);
                const std::optional<bool>* option = nullptr;
                if (head.is(TokenId::KwdIf) || head.is(TokenId::KwdElseIf) || head.is(TokenId::KwdElse))
                    option = &options_->allowShortIfStatementsOnSingleLine;
                else if (head.is(TokenId::KwdWhile) || head.is(TokenId::KwdFor))
                    option = &options_->allowShortLoopsOnSingleLine;

                if (!option || !option->has_value() || **option)
                    continue;

                const uint32_t first = model_->nextPiece(body.doPiece);
                if (first == INVALID_PIECE || model_->gapHasNewline(first) || !FormatPassUtil::canEditGap(*model_, first))
                    continue;

                const Utf8 indent = FormatPassUtil::indentPlusOne(*model_, model_->lineIndentOf(body.headPiece));
                model_->setGapBreak(first, 1, indent.view());
            }
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
                // `#static if X { a } else { b }`.
                if (breakBefore && closesSingleLineBlock(prev))
                    continue;

                if (breakBefore && !model_->gapHasNewline(i))
                    model_->setGapBreak(i, 1, model_->lineIndentOf(prev));
                else if (!breakBefore && model_->gapHasNewline(i))
                    model_->setGapSpaces(i, 1);
            }
        }

        // A `where` clause moves to its own line, one level under
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

        struct CaseArm
        {
            uint32_t colon      = INVALID_PIECE; // the `:` of the label
            uint32_t body       = INVALID_PIECE; // first body piece (INVALID when the arm is empty)
            bool     editable   = false;
            bool     oneLine    = false; // body shares the label line
            bool     joinable   = false; // single one-line statement, no comments, no braces
            bool     splittable = false; // plain statement body (braced / commented arms keep their layout)
        };

        CaseArm analyzeArm(const uint32_t colonPiece) const
        {
            CaseArm arm;
            arm.colon = colonPiece;

            const uint32_t body = model_->nextPiece(colonPiece);
            if (body == INVALID_PIECE)
                return arm;

            const FormatPiece& bodyPiece = model_->piece(body);
            if (bodyPiece.roles.hasAny({FormatRoleE::CaseLabel}) || bodyPiece.is(TokenId::SymRightCurly))
                return arm; // empty arm

            arm.body     = body;
            arm.editable = FormatPassUtil::canEditGap(*model_, body);
            arm.oneLine  = !model_->gapHasNewline(body);
            if (bodyPiece.is(TokenId::SymLeftCurly) || bodyPiece.isComment)
                return arm; // braced or commented bodies keep their layout
            arm.splittable = true;

            const uint32_t caseEnd = findCaseBodyEnd(colonPiece);
            if (caseEnd == INVALID_PIECE)
                return arm;

            // A line break inside a call, an index, or a literal is the wrapping
            // pass's decision, and that pass runs after this one: counting it
            // here makes an arm look long that comes out on one line, and the
            // next run of the formatter would then join the whole switch. Only
            // the breaks this pass owns — the ones outside any list, including
            // every line of a `{ ... }` body — say that the arm is long.
            uint32_t stmtCount = 0;
            uint32_t listDepth = 0;
            bool     joinable  = true;
            for (uint32_t p = body; p <= caseEnd && joinable; p = model_->nextPiece(p))
            {
                if (p == INVALID_PIECE)
                    break;
                const FormatPiece& cur = model_->piece(p);
                if (cur.isComment)
                    joinable = false;
                if (cur.roles.hasAny({FormatRoleE::StmtStart}) && cur.depth == model_->piece(colonPiece).depth)
                    stmtCount++;
                if (p != body && !listDepth && model_->gapHasNewline(p))
                    joinable = false;

                if (cur.is(TokenId::SymLeftParen) || cur.is(TokenId::SymLeftBracket) || cur.hasRole(FormatRoleE::LiteralOpen))
                    listDepth++;
                else if (listDepth && (cur.is(TokenId::SymRightParen) || cur.is(TokenId::SymRightBracket) || cur.hasRole(FormatRoleE::LiteralClose)))
                    listDepth--;

                if (p == caseEnd)
                    break;
            }

            arm.joinable = joinable && stmtCount <= 1;
            return arm;
        }

        void splitArm(const CaseArm& arm) const
        {
            if (arm.editable && arm.oneLine && arm.splittable)
                model_->setGapBreak(arm.body, 1, FormatPassUtil::indentPlusOne(*model_, model_->lineIndentOf(arm.colon)).view());
        }

        void joinArm(const CaseArm& arm) const
        {
            if (arm.editable && !arm.oneLine && arm.joinable)
                model_->setGapSpaces(arm.body, 1);
        }

        // `case` bodies per switch: `uniform` joins every arm onto its label
        // only when the WHOLE switch is made of single-statement arms (jump
        // tables), and expands everything otherwise.
        void runShortCases() const
        {
            const FormatCaseBodyStyle style = options_->caseBodyStyle;
            if (style == FormatCaseBodyStyle::Preserve)
                return;

            for (const FormatBlock& block : model_->blocks())
            {
                if (block.kind != FormatBlockKind::Switch)
                    continue;
                if (!rangeEditable(*model_, block.openPiece, block.closePiece))
                    continue;

                std::vector<CaseArm> arms;
                const uint32_t       labelDepth = model_->piece(block.openPiece).depth + 1;
                for (uint32_t p = block.openPiece + 1; p < block.closePiece; ++p)
                {
                    const FormatPiece& piece = model_->piece(p);
                    if (!piece.removed && piece.hasRole(FormatRoleE::CaseColon) && piece.depth == labelDepth)
                        arms.push_back(analyzeArm(p));
                }
                if (arms.empty())
                    continue;

                switch (style)
                {
                    case FormatCaseBodyStyle::NextLine:
                        for (const CaseArm& arm : arms)
                            splitArm(arm);
                        break;

                    case FormatCaseBodyStyle::SameLine:
                        for (const CaseArm& arm : arms)
                            joinArm(arm);
                        break;

                    case FormatCaseBodyStyle::Uniform:
                    {
                        bool allShort = true;
                        for (const CaseArm& arm : arms)
                        {
                            if (arm.body != INVALID_PIECE && !arm.joinable)
                                allShort = false;
                        }
                        for (const CaseArm& arm : arms)
                        {
                            if (allShort)
                                joinArm(arm);
                            else
                                splitArm(arm);
                        }
                        break;
                    }

                    case FormatCaseBodyStyle::Preserve:
                        break;
                }
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
    void splitSameLineStatements(FormatModel& model)
    {
        if (!model.options().oneStatementPerLine.value_or(false))
            return;

        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            FormatPiece& semi = model.piece(i);
            if (semi.removed || semi.frozen || semi.isNot(TokenId::SymSemiColon))
                continue;

            const uint32_t next = model.nextPiece(i);
            if (next == INVALID_PIECE || model.piece(next).isComment || model.gapHasNewline(next) ||
                model.piece(next).depth != semi.depth || !model.piece(next).hasRole(FormatRoleE::StmtStart) ||
                !FormatPassUtil::canEditGap(model, next) || statementBelongsToSourceSingleLineBlock(model, i))
                continue;

            model.setGapBreak(next, 1, model.lineIndentOf(i));
            model.removePiece(i);
        }
    }

    void normalizeAggregateMembers(FormatModel& model)
    {
        if (!model.options().oneEnumValuePerLine.value_or(false) && !model.options().oneStructFieldPerLine.value_or(false))
            return;

        for (const FormatBlock& block : model.blocks())
        {
            // An anonymous struct written inside an expression or a type — the
            // `{first: u64, count: u64}` of a generic argument — is not a
            // declaration body: exploding it over four lines and dropping its
            // separator commas rewrites a type as if it were a definition.
            const bool isEnum   = block.kind == FormatBlockKind::Enum && model.options().oneEnumValuePerLine.value_or(false);
            const bool isStruct = block.kind == FormatBlockKind::Struct && model.options().oneStructFieldPerLine.value_or(false);
            if ((!isEnum && !isStruct) || block.exprLevel || !rangeEditable(model, block.openPiece, block.closePiece) || blockKeepsMembersSingleLine(model, block))
                continue;

            const uint32_t        innerDepth = model.piece(block.openPiece).depth + 1;
            const FormatRoleE     memberRole = isEnum ? FormatRoleE::EnumValueStart : FormatRoleE::FieldDeclStart;
            std::vector<uint32_t> members;
            std::vector<uint32_t> separators;
            for (uint32_t i = block.openPiece + 1; i < block.closePiece; ++i)
            {
                const FormatPiece& piece = model.piece(i);
                if (!piece.removed && piece.depth == innerDepth && piece.hasRole(memberRole))
                    members.push_back(i);
            }
            if (isStruct)
            {
                // A top-level comma after a complete `name: type` field can
                // separate fields. A comma before the field's `:` belongs to
                // a multi-name declaration such as `x, y: s32` and must stay.
                for (uint32_t i = block.openPiece + 1; i < block.closePiece; ++i)
                {
                    const FormatPiece& separator = model.piece(i);
                    if (separator.removed || separator.depth != innerDepth || separator.isNot(TokenId::SymComma))
                        continue;

                    bool completesField = false;
                    for (uint32_t p = model.prevPiece(i); p != INVALID_PIECE && p > block.openPiece; p = model.prevPiece(p))
                    {
                        const FormatPiece& piece = model.piece(p);
                        if (piece.depth == innerDepth && piece.is(TokenId::SymComma))
                            break;
                        if (piece.depth == innerDepth && piece.roles.hasAny({FormatRoleE::StmtStart, FormatRoleE::FieldDeclStart}))
                            break;
                        if (piece.depth == innerDepth && (piece.is(TokenId::SymColon) || piece.hasRole(FormatRoleE::InitAssign)))
                        {
                            completesField = true;
                            break;
                        }
                    }

                    const uint32_t next = model.nextPiece(i);
                    if (completesField && next != INVALID_PIECE && next < block.closePiece && model.piece(next).depth == innerDepth && std::ranges::find(members, next) == members.end())
                    {
                        model.piece(next).roles.add(FormatRoleE::StmtStart);
                        model.piece(next).roles.add(FormatRoleE::FieldDeclStart);
                        members.push_back(next);
                        separators.push_back(i);
                    }
                }
                std::ranges::sort(members);
            }

            if (members.size() < 2)
                continue;

            if (isEnum)
            {
                for (uint32_t i = block.openPiece + 1; i < block.closePiece; ++i)
                {
                    FormatPiece& piece = model.piece(i);
                    if (!piece.removed && piece.depth == innerDepth && piece.is(TokenId::SymComma))
                        model.removePiece(i);
                }
            }
            else
            {
                for (const uint32_t separator : separators)
                    model.removePiece(separator);
            }

            const Utf8 base(model.lineIndentOf(block.headPiece));
            const Utf8 inner = FormatPassUtil::indentPlusOne(model, base.view());
            for (const uint32_t member : members)
            {
                if (!isStruct || !model.gapHasNewline(member))
                    model.setGapBreak(member, 1, inner.view());
            }
            if (!isStruct || !model.gapHasNewline(block.closePiece))
                model.setGapBreak(block.closePiece, 1, base.view());
        }
    }

    // `using` is part of an aggregate field declaration, never a standalone
    // line. Repair source that separated it from the field name and keep the
    // prefix canonical before aggregate layout and alignment run.
    void normalizeUsingFields(FormatModel& model)
    {
        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            const FormatPiece& usingPiece = model.piece(i);
            if (usingPiece.removed || usingPiece.frozen || usingPiece.isNot(TokenId::KwdUsing) ||
                !usingPiece.hasRole(FormatRoleE::FieldDeclStart))
                continue;

            const uint32_t fieldName = model.nextPiece(i);
            if (fieldName == INVALID_PIECE || model.piece(fieldName).isComment || !FormatPassUtil::canEditGap(model, fieldName))
                continue;

            model.setGapSpaces(fieldName, 1);
        }
    }

    bool isStorageModifier(const FormatPiece& piece)
    {
        return piece.is(TokenId::KwdLate) || piece.is(TokenId::KwdTls) || piece.is(TokenId::KwdGlobal);
    }

    // Storage modifiers govern the declaration that follows them. Keep that relationship
    // visible on one line (`late field: T`, `tls private var value`) while preserving a
    // braced group as its own section.
    void normalizeStorageModifiers(FormatModel& model)
    {
        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            const FormatPiece& modifier = model.piece(i);
            if (modifier.removed || modifier.frozen || !isStorageModifier(modifier))
                continue;

            const uint32_t next = model.nextPiece(i);
            if (next == INVALID_PIECE || model.piece(next).isComment || model.piece(next).is(TokenId::SymLeftCurly) ||
                !model.gapHasNewline(next) || !FormatPassUtil::canEditGap(model, next))
                continue;

            model.setGapSpaces(next, 1);
        }
    }

    // An unbraced access modifier governs exactly one declaration. Keeping the
    // two on one line makes that scope visible and leaves braced access groups
    // as the only section-shaped form.
    void normalizeAccessModifiers(FormatModel& model)
    {
        if (!model.options().inlineAccessModifiers.value_or(false))
            return;

        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            const FormatPiece& modifier = model.piece(i);
            if (modifier.removed || modifier.frozen || !modifier.hasRole(FormatRoleE::AccessModifier))
                continue;

            const uint32_t next = model.nextPiece(i);
            if (next == INVALID_PIECE || model.piece(next).isComment || model.piece(next).is(TokenId::SymLeftCurly) ||
                !model.gapHasNewline(next) || !FormatPassUtil::canEditGap(model, next))
                continue;

            model.setGapSpaces(next, 1);
        }
    }

    // `;` before an end of line is redundant. Same-line separators stay.
    void removeRedundantSemicolons(FormatModel& model)
    {
        if (!model.options().removeRedundantSemicolons.value_or(false))
            return;

        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            const FormatPiece& piece = model.piece(i);
            if (piece.removed || piece.frozen || piece.isNot(TokenId::SymSemiColon))
                continue;
            if (!FormatPassUtil::canEditGap(model, i))
                continue;

            const uint32_t next = model.nextPiece(i);
            if (next != INVALID_PIECE && !model.gapHasNewline(next))
                continue; // same-line successor: `;` still separates
            model.removePiece(i);
        }
    }

    // `[1, 2, 3,]` → `[1, 2, 3]`. A comma sitting against its closing bracket
    // separates nothing; the base writes 38 000 lists without one.
    void removeTrailingCommas(FormatModel& model)
    {
        if (!model.options().removeTrailingCommas.value_or(false))
            return;

        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            const FormatPiece& piece = model.piece(i);
            if (piece.removed || piece.frozen || piece.isNot(TokenId::SymComma) ||
                piece.hasRole(FormatRoleE::ClosureCaptureComma))
                continue;
            if (!FormatPassUtil::canEditGap(model, i))
                continue;

            uint32_t next = model.nextPiece(i);
            while (next != INVALID_PIECE && model.piece(next).isComment)
                next = model.nextPiece(next);
            if (next == INVALID_PIECE)
                continue;

            const FormatPiece& closer = model.piece(next);
            if (closer.isNot(TokenId::SymRightBracket) && closer.isNot(TokenId::SymRightCurly) &&
                closer.isNot(TokenId::SymRightParen))
                continue;

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
        splitSameLineStatements(model);
        normalizeUsingFields(model);
        normalizeAggregateMembers(model);
        normalizeStorageModifiers(model);
        normalizeAccessModifiers(model);
        removeTrailingCommas(model);
    }

    // What makes a `;` redundant is the end of line right after it, and where
    // the lines end is only settled once wrapping has run. Removing earlier
    // leaves the semicolons that wrapping pushes to an end of line, and the
    // next run of the formatter takes them out instead.
    void redundantSemicolons(FormatModel& model)
    {
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
