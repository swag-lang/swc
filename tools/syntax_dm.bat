@echo off
swc_devmode syntax --verify -d ../bin/tests/lexer %1 %2 %3 %4 %5 %6 %7 %8 %9
swc_devmode syntax --verify -d ../bin/tests/parser %1 %2 %3 %4 %5 %6 %7 %8 %9
swc_devmode syntax -d ../bin/tests/legit %1 %2 %3 %4 %5 %6 %7 %8 %9
swc_devmode syntax -d ../bin/tests/sema %1 %2 %3 %4 %5 %6 %7 %8 %9
swc_devmode syntax -d ../bin/std/modules %1 %2 %3 %4 %5 %6 %7 %8 %9
swc_devmode syntax -d ../bin/runtime %1 %2 %3 %4 %5 %6 %7 %8 %9
