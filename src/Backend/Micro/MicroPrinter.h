#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroRegPrintMode.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class Encoder;
class MicroBuilder;

class MicroPrinter
{
public:
    static Utf8 format(const TaskContext& ctx, const MicroStorage& instructions, const MicroOperandStorage& operands, MicroRegPrintMode regPrintMode = MicroRegPrintMode::Default, const Encoder* encoder = nullptr, const MicroBuilder* builder = nullptr);
    static void print(const TaskContext& ctx, const MicroStorage& instructions, const MicroOperandStorage& operands, MicroRegPrintMode regPrintMode = MicroRegPrintMode::Default, const Encoder* encoder = nullptr, const MicroBuilder* builder = nullptr);
};

SWC_END_NAMESPACE();
