#pragma once
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Support/Core/PagedStoreTyped.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class Encoder;

enum class MicroInstrRegPrintMode : uint8_t
{
    Default,
    Virtual,
    Concrete,
};

class MicroInstrPrinter
{
public:
    static std::string format(const TaskContext&                        ctx,
                              const PagedStoreTyped<MicroInstr>&        instructions,
                              const PagedStoreTyped<MicroInstrOperand>& operands,
                              MicroInstrRegPrintMode                    regPrintMode = MicroInstrRegPrintMode::Default,
                              const Encoder*                            encoder      = nullptr,
                              bool                                   colorize = false);

    static void print(const TaskContext&                        ctx,
                      const PagedStoreTyped<MicroInstr>&        instructions,
                      const PagedStoreTyped<MicroInstrOperand>& operands,
                      MicroInstrRegPrintMode                    regPrintMode = MicroInstrRegPrintMode::Default,
                      const Encoder*                            encoder      = nullptr,
                      bool                                   colorize = true);
};

SWC_END_NAMESPACE();
