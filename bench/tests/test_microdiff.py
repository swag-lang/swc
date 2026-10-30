"""Keep static regression reviews sensitive to code changes and failed captures."""
import os
import sys
import tempfile
import unittest
from subprocess import CompletedProcess
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import microdiff as md


MAIN = "  function : Csvagg.__main_0123456789abcdef\n001 010 ret | ret\n"


def instruction(ref, op="", operands=""):
    return {"ref": ref, "op": op, "operands": operands}


class ListingTests(unittest.TestCase):
    def test_label_renumbering_preserves_targets(self):
        a = [instruction(10), instruction(11, "jump_cond", "ne, b32 10")]
        b = [instruction(40), instruction(90, "jump_cond", "ne, b32 40")]
        self.assertEqual(md.normalized(a), md.normalized(b))

    def test_different_branch_targets_remain_visible(self):
        a = [instruction(10), instruction(20), instruction(30, "jump_cond", "ne, b32 10")]
        b = [instruction(10), instruction(20), instruction(30, "jump_cond", "ne, b32 20")]
        self.assertNotEqual(md.normalized(a), md.normalized(b))

    def test_large_constants_and_frame_offsets_remain_visible(self):
        for op, a, b in [
            ("load_reg_imm", "rax, b64, 0x100000", "rax, b64, 0x200000"),
            ("load_reg_mem", "rax, [rsp + 0x10000], b64", "rax, [rsp + 0x20000], b64"),
        ]:
            with self.subTest(op=op):
                self.assertNotEqual(md.normalized([instruction(0, op, a)]),
                                    md.normalized([instruction(0, op, b)]))

    def test_process_pointer_addresses_are_normalized(self):
        for op in ("load_reg_ptr_reloc", "load_reg_ptr_imm"):
            with self.subTest(op=op):
                self.assertEqual(md.normalized([instruction(0, op, "rax, b64, <0x12345678>")]),
                                 md.normalized([instruction(0, op, "rax, b64, <0x87654321>")]))

    def test_renamed_main_is_reported_without_verbose(self):
        rows, quiet = md.compare("csvagg", MAIN.replace("0123456789abcdef", "0"), MAIN, False)
        self.assertEqual(len(rows), 2)
        self.assertTrue(any("added" in row for row in rows))
        self.assertTrue(any("removed" in row for row in rows))
        self.assertEqual(quiet, 0)

    def test_equal_counts_do_not_hide_a_changed_constant(self):
        a = "  function : Csvagg.scan\n001 010 load_reg_imm rax, b64, 0x100000\n"
        b = a.replace("0x100000", "0x200000")
        rows, quiet = md.compare("csvagg", a, b, True)
        self.assertEqual(len(rows), 1)
        self.assertEqual(quiet, 0)

    def test_local_call_target_remains_visible(self):
        a = "  function : Csvagg.scan\n001 010 call_local swag, <0x0> | call Csvagg.old\n"
        b = a.replace("Csvagg.old", "Csvagg.new")
        self.assertNotEqual(md.normalized(md.parse(a)["Csvagg.scan"]),
                            md.normalized(md.parse(b)["Csvagg.scan"]))

    def test_named_call_addresses_do_not_create_false_code_changes(self):
        for op in ("call_local", "call_extern"):
            with self.subTest(op=op):
                a = "  function : Csvagg.scan\n001 010 %s swag, <0x12345678> | call Csvagg.target\n" % op
                b = a.replace("0x12345678", "0x87654321")
                self.assertEqual(md.normalized(md.parse(a)["Csvagg.scan"]),
                                 md.normalized(md.parse(b)["Csvagg.scan"]))
                self.assertNotEqual(md.normalized(md.parse(a)["Csvagg.scan"]),
                                    md.normalized(md.parse(b.replace("swag,", "c,"))["Csvagg.scan"]))

    def test_unnamed_call_addresses_remain_visible(self):
        for natural in ("", " | call <reloc>"):
            a = "  function : Csvagg.scan\n001 010 call_local swag, <0x12345678>" + natural + "\n"
            b = a.replace("0x12345678", "0x87654321")
            self.assertNotEqual(md.normalized(md.parse(a)["Csvagg.scan"]),
                                md.normalized(md.parse(b)["Csvagg.scan"]))

    def test_legacy_indexed_extensions_count_as_memory_reads(self):
        body = [instruction(1, "load_zero_ext_amc_reg_mem", "7 operand(s)"),
                instruction(2, "load_signed_ext_amc_reg_mem", "7 operand(s)")]
        self.assertEqual(md.counts(body), (2, 2, 0))

    def test_loop_target_is_not_the_operand_width(self):
        body = md.parse("  function : Csvagg.scan\n001 110  \n"
                        "002 111 load_reg_mem rax, [rcx], b64 | rax = [rcx]\n"
                        "003 112 jump_cond ne, b32 110 | if ne jump 110\n")["Csvagg.scan"]
        self.assertEqual(md.loops(body), [(2, 1, 0)])


class CaptureTests(unittest.TestCase):
    def capture(self, root, listing=MAIN, output="CHECK=24828641 MS=1", exit_code=0):
        build = CompletedProcess([], 0, listing, "")
        run = CompletedProcess([], exit_code, output, "")
        with patch.object(md.tc, "swag_dependency_api_files", return_value=[]), \
             patch.object(md.tc, "swag_files", return_value=[]), \
             patch.object(md.subprocess, "run", side_effect=[build, run]) as process:
            result = md.build("compiler", "csvagg", "release", 6, root)
        return result, process.call_args_list

    def test_capture_forces_rebuild_and_uses_private_cache(self):
        with tempfile.TemporaryDirectory() as root:
            (listing, check), calls = self.capture(root)
            self.assertEqual(check, "24828641")
            self.assertEqual(listing, MAIN)
            self.assertIn("--rebuild", calls[0].args[0])
            self.assertEqual(calls[0].kwargs["env"]["TEMP"], os.path.join(root, "csvagg", "temp"))
            self.assertTrue(os.path.isfile(os.path.join(root, "csvagg", "micro.txt")))

    def test_successful_exit_without_checksum_is_rejected(self):
        with tempfile.TemporaryDirectory() as root, self.assertRaisesRegex(SystemExit, "checksum missing"):
            self.capture(root, output="")

    def test_nonzero_exit_with_checksum_is_rejected(self):
        with tempfile.TemporaryDirectory() as root, self.assertRaisesRegex(SystemExit, "exited with 1"):
            self.capture(root, exit_code=1)

    def test_missing_task_listing_is_rejected(self):
        with tempfile.TemporaryDirectory() as root, self.assertRaisesRegex(SystemExit, "no task main listing"):
            self.capture(root, listing="")


if __name__ == "__main__":
    unittest.main()
