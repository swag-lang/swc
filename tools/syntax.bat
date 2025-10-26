@echo off

swc syntax -d ../tests -d ../../swag/bin/testsuite/tests/compiler/src/legacy -d ../../swag/bin/std -d ../../swag/bin/examples -d ../../swag/bin/runtime -d ../../swag/bin/reference %1 %2 %3 %4 %5
