@echo off
swc syntax --verify -d ../bin/tests/lexer %1 %2 %3 %4 %5 %6 %7 %8 %9
swc syntax --verify -d ../bin/tests/parser %1 %2 %3 %4 %5 %6 %7 %8 %9
swc syntax -d ../bin/tests/legit %1 %2 %3 %4 %5 %6 %7 %8 %9
swc syntax -d ../bin/std/modules %1 %2 %3 %4 %5 %6 %7 %8 %9
swc syntax -d ../bin/runtime %1 %2 %3 %4 %5 %6 %7 %8 %9
