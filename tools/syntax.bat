@echo off

swc syntax --folder ../tests %1 %2 %3 %4 %5
swc syntax --folder ../../swag/bin/testsuite/tests/compiler/src/legacy %1 %2 %3 %4 %5
swc syntax --folder ../../swag/bin/std %1 %2 %3 %4 %5
swc syntax --folder ../../swag/bin/examples %1 %2 %3 %4 %5
swc syntax --folder ../../swag/bin/runtime %1 %2 %3 %4 %5
swc syntax --folder ../../swag/bin/reference %1 %2 %3 %4 %5
