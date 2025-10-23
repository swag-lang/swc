#include "pch.h"

#include "Global.h"
#include "Main/Swc.h"

int main(int argc, char* argv[])
{
    auto& glb = Global::get();
    glb.initialize();

    Swc swc;
    return swc.go(argc, argv);
}
