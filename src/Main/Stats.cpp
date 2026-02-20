#include "pch.h"
#include "Main/Stats.h"
#include "Main/Global.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

void Stats::print(const TaskContext& ctx) const
{
    Logger::ScopedLock loggerLock(ctx.global().logger());

    constexpr auto colorHeader = LogColor::Yellow;
    constexpr auto colorMsg    = LogColor::White;

    Logger::printHeaderDot(ctx, colorHeader, "numWorkers", colorMsg, Utf8Helper::toNiceBigNumber(ctx.global().jobMgr().numWorkers()));
    Logger::printHeaderDot(ctx, colorHeader, "timeTotal", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeTotal.load())));

#if SWC_HAS_STATS
    // Frontend counts
    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numFiles", colorMsg, Utf8Helper::toNiceBigNumber(numFiles.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numTokens", colorMsg, Utf8Helper::toNiceBigNumber(numTokens.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numAstNodes", colorMsg, Utf8Helper::toNiceBigNumber(numAstNodes.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numVisitedAstNodes", colorMsg, Utf8Helper::toNiceBigNumber(numVisitedAstNodes.load()));

    // Semantic model counts
    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "count.sema.numConstants", colorMsg, Utf8Helper::toNiceBigNumber(numConstants.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.sema.numTypes", colorMsg, Utf8Helper::toNiceBigNumber(numTypes.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.sema.numIdentifiers", colorMsg, Utf8Helper::toNiceBigNumber(numIdentifiers.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.sema.numSymbols", colorMsg, Utf8Helper::toNiceBigNumber(numSymbols.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.sema.numCodeGenFunctions", colorMsg, Utf8Helper::toNiceBigNumber(numCodeGenFunctions.load()));

    // Backend micro counts
    Logger::print(ctx, "\n");
    const size_t numMicroNoOptim      = numMicroInstrNoOptim.load();
    const size_t numMicroFinal        = numMicroInstrFinal.load();
    const size_t numMicroOpNoOptim    = numMicroOperandsNoOptim.load();
    const size_t numMicroOpFinal      = numMicroOperandsFinal.load();
    const size_t numMicroOptimRemoved = numMicroInstrOptimRemoved.load();
    const size_t numMicroOptimAdded   = numMicroInstrOptimAdded.load();

    Logger::printHeaderDot(ctx, colorHeader, "count.micro.numInstrNoOptim", colorMsg, Utf8Helper::toNiceBigNumber(numMicroNoOptim));
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.numInstrFinal", colorMsg, Utf8Helper::toNiceBigNumber(numMicroFinal));
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.numOperandsNoOptim", colorMsg, Utf8Helper::toNiceBigNumber(numMicroOpNoOptim));
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.numOperandsFinal", colorMsg, Utf8Helper::toNiceBigNumber(numMicroOpFinal));

    const int64_t numMicroPipelineDelta     = static_cast<int64_t>(numMicroNoOptim) - static_cast<int64_t>(numMicroFinal);
    const char    numMicroPipelineDeltaSign = numMicroPipelineDelta >= 0 ? '+' : '-';
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.pipelineDelta", colorMsg, std::format("{}{}", numMicroPipelineDeltaSign, Utf8Helper::toNiceBigNumber(static_cast<size_t>(std::abs(numMicroPipelineDelta)))));

    double pipelineRemovedPct = 0.0;
    if (numMicroNoOptim != 0)
        pipelineRemovedPct = 100.0 * static_cast<double>(numMicroPipelineDelta) / static_cast<double>(numMicroNoOptim);
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.pipelineRemovedPct", colorMsg, std::format("{:.2f}%", pipelineRemovedPct));

    const int64_t numMicroOptimNet     = static_cast<int64_t>(numMicroOptimRemoved) - static_cast<int64_t>(numMicroOptimAdded);
    const char    numMicroOptimNetSign = numMicroOptimNet >= 0 ? '+' : '-';
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.optimRemoved", colorMsg, Utf8Helper::toNiceBigNumber(numMicroOptimRemoved));
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.optimAdded", colorMsg, Utf8Helper::toNiceBigNumber(numMicroOptimAdded));
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.optimNet", colorMsg, std::format("{}{}", numMicroOptimNetSign, Utf8Helper::toNiceBigNumber(static_cast<size_t>(std::abs(numMicroOptimNet)))));

    double optimRemovedPct = 0.0;
    if (numMicroNoOptim != 0)
        optimRemovedPct = 100.0 * static_cast<double>(numMicroOptimNet) / static_cast<double>(numMicroNoOptim);
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.optimRemovedPct", colorMsg, std::format("{:.2f}%", optimRemovedPct));

    // Time
    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "time.frontend.loadFile", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLoadFile.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.frontend.lexer", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLexer.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.frontend.parser", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeParser.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.backend.codegen", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeCodeGen.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.backend.microLower", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeMicroLower.load())));

    // Memory
    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "mem.process.maxAllocated", colorMsg, Utf8Helper::toNiceSize(memMaxAllocated.load()));
    Logger::printHeaderDot(ctx, colorHeader, "mem.sema.constants", colorMsg, Utf8Helper::toNiceSize(memConstants.load()));
    Logger::printHeaderDot(ctx, colorHeader, "mem.sema.types", colorMsg, Utf8Helper::toNiceSize(memTypes.load()));
    Logger::printHeaderDot(ctx, colorHeader, "mem.sema.symbols", colorMsg, Utf8Helper::toNiceSize(memSymbols.load()));
    Logger::printHeaderDot(ctx, colorHeader, "mem.micro.storageNoOptim", colorMsg, Utf8Helper::toNiceSize(memMicroStorageNoOptim.load()));
    Logger::printHeaderDot(ctx, colorHeader, "mem.micro.storageFinal", colorMsg, Utf8Helper::toNiceSize(memMicroStorageFinal.load()));
#endif

    Logger::print(ctx, "\n");
}

SWC_END_NAMESPACE();
