#!/usr/bin/env python3
"""Headless native preflight tests using explicit synthetic ELF fixtures.

These validate checker and launcher boundaries, not Flutter GUI acceptance.
Only a C/C++ compiler, the system C/math runtime, and Python's standard library
are needed for tests. The installed launcher does not require Python.
"""

import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "experiments/maintenance_local/linux/runner/runtime_check.cc"
LAUNCHER = ROOT / "experiments/maintenance_local/linux/distribution/vortice-maintenance"
RUST_SYMBOLS = (
    "frbgen_sync_lab_rust_arc_increment_strong_count_"
    "RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDocumentSession",
    "frbgen_sync_lab_rust_arc_decrement_strong_count_"
    "RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDocumentSession",
)
LIBRARIES = {
    "flutter": "libflutter_linux_gtk.so",
    "file_selector": "libfile_selector_linux_plugin.so",
    "rust": "librust_lib_sync_lab.so",
    "sqlite": "libsqlite3.so",
}
SQLITE_FIXTURE = r'''
#include <string.h>
#include <math.h>
struct sqlite3 { int ready; };
struct sqlite3_stmt { int steps; };
static struct sqlite3 database;
static struct sqlite3_stmt statement;
int sqlite3_open_v2(const char* name, struct sqlite3** out, int flags, const char* vfs) {
  if (strcmp(name, ":memory:") || flags != (2 | 4 | 128 | 32768) || vfs) return 1;
#ifdef OPEN_FAIL
  *out = 0; return 1;
#else
  database.ready = 1; *out = &database; return 0;
#endif
}
int sqlite3_prepare_v2(struct sqlite3* db, const char* sql, int bytes,
                       struct sqlite3_stmt** out, const char** tail) {
  if (db != &database || !db->ready || strcmp(sql, "SELECT 40 + 2") || bytes != -1 || tail) return 1;
#ifdef PREPARE_FAIL
  *out = 0; return 1;
#else
  statement.steps = 0; *out = &statement; return 0;
#endif
}
int sqlite3_step(struct sqlite3_stmt* stmt) {
  if (stmt != &statement) return 1;
#ifdef ROW_FAIL
  return 101;
#elif defined(TRAILING_FAIL)
  return 100;
#else
  return stmt->steps++ == 0 ? 100 : 101;
#endif
}
long long sqlite3_column_int64(struct sqlite3_stmt* stmt, int column) {
  if (stmt != &statement || column != 0) return -1;
#ifdef VALUE_FAIL
  return 41;
#elif defined(REQUIRE_MATH)
  volatile double input = 42.9;
  return (int)trunc(input);
#else
  return 42;
#endif
}
int sqlite3_finalize(struct sqlite3_stmt* stmt) {
#ifdef FINALIZE_FAIL
  return 1;
#else
  return stmt == &statement ? 0 : 1;
#endif
}
int sqlite3_close_v2(struct sqlite3* db) {
#ifdef CLOSE_FAIL
  return 1;
#else
  if (db != &database) return 1;
  db->ready = 0; return 0;
#endif
}
'''


class RuntimeCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cxx = shutil.which("g++") or shutil.which("c++")
        cls.cc = shutil.which("cc") or shutil.which("gcc")
        if not cls.cxx or not cls.cc:
            raise unittest.SkipTest("Native fixture tests require C and C++ compilers")
        cls.build_temporary = tempfile.TemporaryDirectory(prefix="vortice-native-fixtures-")
        cls.build = Path(cls.build_temporary.name)
        cls.checker = cls.build / "vortice-runtime-check"
        cls.command([cls.cxx, "-std=c++14", "-Wall", "-Wextra", "-Werror",
                     str(CHECKER), "-ldl", "-o", str(cls.checker)])
        cls.fixtures = {}
        for component, source in {
            "flutter": "long fl_engine_get_type(void) { return 0; }",
            "file_selector": "void file_selector_plugin_register_with_registrar(void* p) { (void)p; }",
            "rust": "\n".join(f"void {symbol}(void* p) {{ (void)p; }}" for symbol in RUST_SYMBOLS),
            "sqlite": SQLITE_FIXTURE,
            "missing_symbol": "void fixture_unrelated_symbol(void) {}",
            "unresolved_symbol": "extern void private_loader_marker(void); long fl_engine_get_type(void) { private_loader_marker(); return 0; }",
            "crash": "__attribute__((constructor)) static void fail(void) { __builtin_trap(); } long fl_engine_get_type(void) { return 0; }",
            "hang": "#include <signal.h>\n__attribute__((constructor)) static void hang(void) { sigset_t mask; sigemptyset(&mask); sigaddset(&mask, SIGALRM); sigprocmask(SIG_BLOCK, &mask, 0); for (;;) {} } long fl_engine_get_type(void) { return 0; }",
            "noisy": '#include <unistd.h>\n__attribute__((constructor)) static void noise(void) { write(1, "PRIVATE constructor data\\n", 25); write(2, "PRIVATE constructor data\\n", 25); } long fl_engine_get_type(void) { return 0; }',
            "closed_streams": "#include <unistd.h>\n__attribute__((constructor)) static void silence(void) { close(1); close(2); } long fl_engine_get_type(void) { return 0; }",
            "destructor": '#include <unistd.h>\n__attribute__((destructor)) static void teardown(void) { write(1, "PRIVATE teardown data\\n", 22); write(2, "PRIVATE teardown data\\n", 22); for (;;) {} } long fl_engine_get_type(void) { return 0; }',
        }.items():
            cls.fixtures[component] = cls.compile_shared(component, source)
        for failure in ("OPEN_FAIL", "PREPARE_FAIL", "ROW_FAIL", "VALUE_FAIL",
                        "TRAILING_FAIL", "FINALIZE_FAIL", "CLOSE_FAIL", "REQUIRE_MATH"):
            cls.fixtures[failure] = cls.compile_shared(failure, SQLITE_FIXTURE,
                                                       [f"-D{failure}", "-fno-builtin-trunc"])
        dependency = cls.compile_shared("private_system_dependency", "long fixture_dependency(void) { return 0; }",
                                        ["-Wl,-soname,libgtk-3.so.runtime-fixture"])
        cls.fixtures["missing_gtk"] = cls.compile_shared(
            "missing_gtk", "extern long fixture_dependency(void); long fl_engine_get_type(void) { return fixture_dependency(); }",
            [str(dependency), "-Wl,-rpath,$ORIGIN"])
        cls.fixtures["missing_system_dependency"] = cls.compile_shared(
            "missing_dependency", "extern long fixture_dependency(void); long fl_engine_get_type(void) { return fixture_dependency(); }",
            [str(cls.compile_shared("private_generic_dependency", "long fixture_dependency(void) { return 0; }",
                                    ["-Wl,-soname,libprivate-system-runtime-fixture.so"])),
             "-Wl,-rpath,$ORIGIN"])
        cls.fixtures["flutter_soname"] = cls.compile_shared(
            "libflutter_linux_gtk", "long fl_engine_get_type(void) { return 0; }",
            ["-Wl,-soname,libflutter_linux_gtk.so"])
        for name, runpath in (("selector_relative", "$ORIGIN"),
                              ("selector_broken", "/PRIVATE/source-checkout/lib")):
            cls.fixtures[name] = cls.compile_shared(
                name, "extern long fl_engine_get_type(void); void file_selector_plugin_register_with_registrar(void* p) { (void)p; fl_engine_get_type(); }",
                [str(cls.fixtures["flutter_soname"]), f"-Wl,-rpath,{runpath}"])

    @classmethod
    def tearDownClass(cls):
        cls.build_temporary.cleanup()

    @classmethod
    def command(cls, arguments, **options):
        return subprocess.run(arguments, check=True, text=True, capture_output=True,
                              timeout=30, **options)

    @classmethod
    def compile_shared(cls, name, source, flags=()):
        source_path = cls.build / f"{name}.c"
        library = cls.build / f"{name}.so"
        source_path.write_text(source)
        cls.command([cls.cc, "-shared", "-fPIC", str(source_path), *flags,
                     "-o", str(library)])
        return library

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vortice-runtime-test-")
        self.base = Path(self.temporary.name)
        self.bundle = self.base / "portable bundle λ with spaces"
        (self.bundle / "lib").mkdir(parents=True)
        shutil.copy2(self.checker, self.bundle / "vortice-runtime-check")
        shutil.copy2(LAUNCHER, self.bundle / "vortice-maintenance")
        for component in LIBRARIES:
            self.replace_library(component, component)
        self.app_log = self.base / "application-arguments.txt"
        self.app = self.bundle / "maintenance_local"
        self.app.write_text('#!/bin/sh\nprintf "<%s>\\n" "$@" > "$FAKE_APP_LOG"\nexit 23\n')
        self.app.chmod(0o755)
        self.environment = dict(os.environ, FAKE_APP_LOG=str(self.app_log))
        self.environment.pop("DISPLAY", None)
        self.environment.pop("WAYLAND_DISPLAY", None)

    def tearDown(self):
        self.temporary.cleanup()

    def replace_library(self, component, fixture):
        target = self.bundle / "lib" / LIBRARIES[component]
        shutil.copy2(self.fixtures[fixture], target)
        return target

    def run_check(self, *arguments, executable=None, timeout=15):
        return subprocess.run([str(executable or self.bundle / "vortice-runtime-check"), *arguments],
                              cwd=self.base, env=self.environment, text=True,
                              capture_output=True, timeout=timeout)

    def run_launcher(self, *arguments, executable=None):
        return subprocess.run([str(executable or self.bundle / "vortice-maintenance"), *arguments],
                              cwd=self.base, env=self.environment, text=True,
                              capture_output=True, timeout=15)

    def report(self, result, expected_code=0):
        self.assertEqual(result.returncode, expected_code, result.stderr)
        self.assertEqual(result.stderr, "")
        data = json.loads(result.stdout)
        self.assertEqual(set(data), {"schema_version", "ok", "status", "checks"})
        self.assertEqual(data["schema_version"], 1)
        self.assertIs(data["ok"], expected_code == 0)
        self.assertNotIn(str(self.base), result.stdout)
        self.assertNotIn(str(self.build), result.stdout)
        self.assertNotIn("private_loader_marker", result.stdout)
        self.assertNotIn("libprivate-system-runtime-fixture", result.stdout)
        self.assertNotIn("PRIVATE", result.stdout)
        self.assertFalse(self.app_log.exists())
        return data

    def assert_component_failure(self, component, status):
        data = self.report(self.run_check("--json"), 1)
        self.assertEqual(data["status"], "failed")
        checks = {check["component"]: check for check in data["checks"]}
        self.assertEqual(set(checks), {"system_math", *LIBRARIES})
        self.assertEqual(checks[component]["status"], status)
        for other, check in checks.items():
            self.assertEqual(set(check), {"component", "status", "message"})
            if other != component:
                self.assertEqual(check["status"], "ok")

    def test_valid_native_fixtures_and_memory_query_with_no_display(self):
        data = self.report(self.run_check("--json"))
        self.assertEqual(data["status"], "ok")
        self.assertEqual([check["component"] for check in data["checks"]],
                         ["system_math", "file_selector", "flutter", "rust", "sqlite"])
        self.assertTrue(all(check["status"] == "ok" for check in data["checks"]))

    def test_math_symbols_loaded_for_sqlite_without_libm_needed(self):
        self.replace_library("sqlite", "REQUIRE_MATH")
        self.report(self.run_check("--json"))
        # This same fixture cannot load in a fresh process without global libm.
        source = self.build / "math_probe.c"
        executable = self.build / "math_probe"
        source.write_text('#include <dlfcn.h>\nint main(int argc, char** argv) { (void)argc; return dlopen(argv[1], RTLD_NOW | RTLD_LOCAL) ? 0 : 1; }\n')
        self.command([self.cc, str(source), "-ldl", "-o", str(executable)])
        result = subprocess.run([str(executable), str(self.bundle / "lib/libsqlite3.so")],
                                capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 1)

    def test_every_missing_library_is_reported_without_path(self):
        for component, filename in LIBRARIES.items():
            with self.subTest(component=component):
                path = self.bundle / "lib" / filename
                path.unlink()
                self.assert_component_failure(component, "missing_library")
                self.replace_library(component, component)

    def test_corrupt_file_directory_and_fifo_are_bounded(self):
        path = self.bundle / "lib" / LIBRARIES["flutter"]
        path.write_bytes(b"PRIVATE raw library diagnostic\n")
        self.assert_component_failure("flutter", "invalid_library")
        path.unlink()
        path.mkdir()
        self.assert_component_failure("flutter", "invalid_library")
        path.rmdir()
        os.mkfifo(path)
        self.assert_component_failure("flutter", "invalid_library")

    def test_wrong_architecture_class_and_endianness(self):
        path = self.bundle / "lib" / LIBRARIES["flutter"]
        original = path.read_bytes()
        for offset, replacement in ((18, b"\xff\xff"),
                                    (4, bytes([1 if original[4] == 2 else 2])),
                                    (5, bytes([2 if original[5] == 1 else 1]))):
            with self.subTest(offset=offset):
                modified = bytearray(original)
                modified[offset:offset + len(replacement)] = replacement
                path.write_bytes(modified)
                self.assert_component_failure("flutter", "wrong_architecture")

    def test_non_shared_elf_is_invalid(self):
        path = self.bundle / "lib" / LIBRARIES["flutter"]
        modified = bytearray(path.read_bytes())
        byte_order = "<" if modified[5] == 1 else ">"
        modified[16:18] = struct.pack(byte_order + "H", 2)
        path.write_bytes(modified)
        self.assert_component_failure("flutter", "invalid_library")

    def test_every_required_library_abi_has_a_symbol_check(self):
        for component in LIBRARIES:
            with self.subTest(component=component):
                self.replace_library(component, "missing_symbol")
                self.assert_component_failure(component, "missing_symbol")
                self.replace_library(component, component)

    def test_unresolved_symbol_uses_fixed_diagnostic(self):
        self.replace_library("flutter", "unresolved_symbol")
        self.assert_component_failure("flutter", "incompatible_library")
        human = self.run_check()
        self.assertEqual(human.returncode, 1)
        self.assertEqual(human.stdout, "")
        self.assertIn("unresolved symbol", human.stderr)
        self.assertNotIn("private_loader_marker", human.stderr)
        self.assertNotIn(str(self.base), human.stderr)

    def test_missing_system_dependency_and_gtk_have_correct_fixed_language(self):
        for fixture, status in (("missing_system_dependency", "missing_system_dependency"),
                                ("missing_gtk", "missing_gtk")):
            with self.subTest(fixture=fixture):
                self.replace_library("flutter", fixture)
                self.assert_component_failure("flutter", status)

    def test_every_sqlite_query_and_cleanup_failure_is_reported(self):
        for fixture in ("OPEN_FAIL", "PREPARE_FAIL", "ROW_FAIL", "VALUE_FAIL",
                        "TRAILING_FAIL", "FINALIZE_FAIL", "CLOSE_FAIL"):
            with self.subTest(fixture=fixture):
                self.replace_library("sqlite", fixture)
                self.assert_component_failure("sqlite", "query_failed")

    def test_failing_constructor_has_fixed_safe_json(self):
        self.replace_library("flutter", "crash")
        data = self.report(self.run_check("--json"), 1)
        self.assertEqual(data["status"], "native_library_error")
        self.assertEqual(data["checks"], [])

    def test_hanging_constructor_is_bounded(self):
        self.replace_library("flutter", "hang")
        started = time.monotonic()
        data = self.report(self.run_check("--json", timeout=13), 1)
        self.assertEqual(data["status"], "timeout")
        self.assertLess(time.monotonic() - started, 13)

    def test_constructor_output_and_closed_streams_do_not_affect_parent_json(self):
        for fixture in ("noisy", "closed_streams"):
            with self.subTest(fixture=fixture):
                self.replace_library("flutter", fixture)
                self.report(self.run_check("--json"))

    def test_native_destructors_are_not_run_after_the_report(self):
        self.replace_library("flutter", "destructor")
        self.report(self.run_check("--json", timeout=5))

    def test_selector_relative_runpath_is_checked_before_flutter_is_cached(self):
        self.replace_library("flutter", "flutter_soname")
        self.replace_library("file_selector", "selector_relative")
        self.report(self.run_check("--json"))
        self.replace_library("file_selector", "selector_broken")
        self.assert_component_failure("file_selector", "missing_system_dependency")

    def test_help_and_invalid_arguments_never_echo_input(self):
        help_result = self.run_check("--help")
        self.assertEqual(help_result.returncode, 0)
        self.assertIn("Usage:", help_result.stdout)
        self.assertEqual(help_result.stderr, "")
        for arguments in (("PRIVATE-argument",), ("--json", "PRIVATE-argument"),
                          ("--json", "--json"), ("--help", "--json")):
            with self.subTest(arguments=arguments):
                result = self.run_check(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertNotIn("PRIVATE-argument", result.stdout + result.stderr)
                if "--json" in arguments:
                    self.assertEqual(self.report(result, 2)["status"], "invalid_arguments")
        self.assertFalse(self.app_log.exists())

    def test_checker_symlink_uses_executable_bundle_root(self):
        link = self.base / "checker alias λ"
        link.symlink_to(self.bundle / "vortice-runtime-check")
        self.report(self.run_check("--json", executable=link))

    def test_closed_caller_stdin_and_stderr_do_not_replace_worker_ipc(self):
        def close_unused_streams():
            os.close(0)
            os.close(2)
        result = subprocess.run([str(self.bundle / "vortice-runtime-check"), "--json"],
                                cwd=self.base, env=self.environment, text=True,
                                capture_output=True, timeout=5,
                                preexec_fn=close_unused_streams)
        self.report(result)

    def test_launcher_check_only_json_and_human_never_start_application(self):
        self.report(self.run_launcher("--check-runtime", "--json"))
        result = self.run_launcher("--check-runtime")
        self.assertEqual(result.returncode, 0)
        self.assertIn("Runtime check passed", result.stdout)
        self.assertEqual(result.stderr, "")
        self.assertFalse(self.app_log.exists())

    def test_launcher_preserves_arguments_and_application_exit_code(self):
        arguments = ("two words", "", "λ", "literal;$HOME", "*", "--app-option", "line\nbreak")
        result = self.run_launcher(*arguments)
        self.assertEqual(result.returncode, 23)
        self.assertEqual(self.app_log.read_text(), "".join(f"<{argument}>\n" for argument in arguments))

    def test_launcher_failure_stops_before_application(self):
        (self.bundle / "lib" / LIBRARIES["rust"]).unlink()
        result = self.run_launcher("app argument")
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing_library", result.stderr)
        self.assertFalse(self.app_log.exists())

    def test_launcher_relative_and_absolute_symlink_chain_with_path(self):
        aliases = self.base / "aliases with spaces λ"
        aliases.mkdir()
        first = aliases / "first link"
        first.symlink_to(os.path.relpath(self.bundle / "vortice-maintenance", aliases))
        last = aliases / "vortice-maintenance"
        last.symlink_to(first)
        self.environment["PATH"] = str(aliases) + os.pathsep + os.defpath
        self.report(self.run_launcher("--check-runtime", "--json", executable="vortice-maintenance"))
        self.report(self.run_launcher("--check-runtime", "--json", executable=last))

    def test_launcher_relative_path_from_caller_directory(self):
        relative = os.path.relpath(self.bundle / "vortice-maintenance", self.base)
        self.report(self.run_launcher("--check-runtime", "--json", executable=relative))

    def test_launcher_invalid_check_only_arguments_do_not_start_application(self):
        for arguments in (("--check-runtime", "private-marker"),
                          ("--check-runtime", "--json", "private-marker")):
            with self.subTest(arguments=arguments):
                result = self.run_launcher(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertNotIn("private-marker", result.stderr)
                self.assertFalse(self.app_log.exists())

    def test_launcher_missing_checker_or_application_has_fixed_message(self):
        checker = self.bundle / "vortice-runtime-check"
        checker.unlink()
        result = self.run_launcher("--check-runtime")
        self.assertEqual(result.returncode, 1)
        self.assertIn("checker is missing", result.stderr)
        self.assertNotIn(str(self.base), result.stderr)
        shutil.copy2(self.checker, checker)
        self.app.unlink()
        result = self.run_launcher()
        self.assertEqual(result.returncode, 1)
        self.assertIn("application is missing", result.stderr)
        self.assertFalse(self.app_log.exists())

    def test_launcher_missing_checker_has_safe_json(self):
        (self.bundle / "vortice-runtime-check").unlink()
        data = self.report(self.run_launcher("--check-runtime", "--json"), 1)
        self.assertEqual(data["status"], "checker_unavailable")
        self.assertEqual(data["checks"], [])

    def test_launcher_non_executable_checker_has_safe_json(self):
        checker = self.bundle / "vortice-runtime-check"
        checker.chmod(0o644)
        data = self.report(self.run_launcher("--check-runtime", "--json"), 1)
        self.assertEqual(data["status"], "checker_unavailable")
        self.assertEqual(data["checks"], [])

    def test_launcher_unavailable_checker_preserves_human_modes(self):
        checker = self.bundle / "vortice-runtime-check"
        for missing in (False, True):
            if missing:
                checker.unlink()
            else:
                checker.chmod(0o644)
            for arguments in ((), ("--check-runtime",), ("--json",),
                              ("--check-runtime", "--json", "PRIVATE-argument"),
                              ("--check-runtime", "PRIVATE-argument", "--json")):
                with self.subTest(missing=missing, arguments=arguments):
                    result = self.run_launcher(*arguments)
                    self.assertEqual(result.returncode, 1)
                    self.assertEqual(result.stdout, "")
                    self.assertEqual(
                        result.stderr,
                        "The Vortice Maintenance native runtime checker is missing or not executable.\n")
                    self.assertFalse(self.app_log.exists())

    def test_launcher_forwards_json_only_for_valid_check_only_invocation(self):
        checker_log = self.base / "checker-arguments.txt"
        self.environment["FAKE_CHECKER_LOG"] = str(checker_log)
        checker = self.bundle / "vortice-runtime-check"
        checker.write_text(
            '#!/bin/sh\nprintf "<%s>\\n" "$@" > "$FAKE_CHECKER_LOG"\n'
            'if [ "${1-}" = "--json" ]; then\n'
            '  printf "%s\\n" \'{"schema_version":1,"ok":false,"status":"failed","checks":[]}\'\n'
            'else\n  printf "%s\\n" "Runtime check failed: fixture unavailable." >&2\nfi\n'
            'exit 1\n')
        for arguments, forwarded in ((("--check-runtime", "--json"), "<--json>\n"),
                                     (("--check-runtime",), "<>\n"),
                                     (("--json",), "<>\n")):
            with self.subTest(arguments=arguments):
                result = self.run_launcher(*arguments)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(checker_log.read_text(), forwarded)
                if arguments == ("--check-runtime", "--json"):
                    self.assertEqual(self.report(result, 1)["status"], "failed")
                else:
                    self.assertEqual(result.stdout, "")
                    self.assertEqual(result.stderr, "Runtime check failed: fixture unavailable.\n")
                self.assertFalse(self.app_log.exists())

    def test_launcher_pre_main_loader_errors_are_private_and_have_safe_json(self):
        checker = self.bundle / "vortice-runtime-check"
        for code in (0, 1, 126, 127):
            checker.write_text(f'#!/bin/sh\nprintf "%s\\n" "PRIVATE loader search path" >&2\nexit {code}\n')
            for arguments in (("--check-runtime", "--json"), ("--check-runtime",), ("normal",)):
                with self.subTest(code=code, arguments=arguments):
                    result = self.run_launcher(*arguments)
                    self.assertEqual(result.returncode, 1)
                    self.assertNotIn("PRIVATE", result.stdout + result.stderr)
                    self.assertFalse(self.app_log.exists())
                    if "--json" in arguments:
                        self.assertEqual(self.report(result, 1)["status"], "checker_unavailable")
                    else:
                        self.assertIn("native checker cannot start", result.stderr)


if __name__ == "__main__":
    unittest.main()
