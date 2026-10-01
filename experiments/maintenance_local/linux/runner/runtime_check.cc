// Headless preflight for the relocatable Linux bundle. Do not initialize GTK,
// Flutter, Dart, Rust application state, or a user database here.
#include <dlfcn.h>
#include <elf.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

volatile sig_atomic_t json_output = 0;
constexpr unsigned int kDeadlineSeconds = 10;

struct Check {
  const char* component;
  const char* status;
  const char* message;
};

Check Ok(const char* component) {
  return {component, "ok", "Native prerequisite is available."};
}

bool ExecutableRoot(std::string* root) {
  // /proc identifies the actual checker even when PATH or a symlink was used.
  std::vector<char> path(4096);
  const ssize_t count = readlink("/proc/self/exe", path.data(), path.size() - 1);
  if (count <= 0 || static_cast<size_t>(count) == path.size() - 1) return false;
  path[static_cast<size_t>(count)] = '\0';
  char* canonical = realpath(path.data(), nullptr);
  if (canonical == nullptr) return false;
  const std::string executable(canonical);
  free(canonical);
  const size_t slash = executable.find_last_of('/');
  if (slash == std::string::npos) return false;
  *root = executable.substr(0, slash);
  return true;
}

unsigned int NativeMachine() {
#if defined(__x86_64__)
  return EM_X86_64;
#elif defined(__aarch64__)
  return EM_AARCH64;
#elif defined(__i386__)
  return EM_386;
#elif defined(__arm__)
  return EM_ARM;
#elif defined(__riscv)
  return EM_RISCV;
#elif defined(__powerpc64__)
  return EM_PPC64;
#elif defined(__powerpc__)
  return EM_PPC;
#else
  return EM_NONE;
#endif
}

Check InspectElf(const char* component, const std::string& path) {
  const int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NONBLOCK);
  if (fd < 0) {
    return {component, errno == ENOENT ? "missing_library" : "unreadable_library",
            "A required bundled native library is missing or unreadable."};
  }
  struct stat metadata;
  unsigned char header[sizeof(Elf64_Ehdr)] = {};
  ssize_t count = -1;
  if (fstat(fd, &metadata) == 0 && S_ISREG(metadata.st_mode)) {
    do {
      count = read(fd, header, sizeof(header));
    } while (count < 0 && errno == EINTR);
  }
  close(fd);
  if (count < static_cast<ssize_t>(sizeof(Elf32_Ehdr)) ||
      memcmp(header, ELFMAG, SELFMAG) != 0 || header[EI_VERSION] != EV_CURRENT) {
    return {component, "invalid_library",
            "A bundled native library is not a valid shared ELF library."};
  }
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
  constexpr unsigned char native_data = ELFDATA2LSB;
#else
  constexpr unsigned char native_data = ELFDATA2MSB;
#endif
  const unsigned char native_class = sizeof(void*) == 8 ? ELFCLASS64 : ELFCLASS32;
  if (header[EI_CLASS] != native_class || header[EI_DATA] != native_data) {
    return {component, "wrong_architecture",
            "A bundled native library does not match this checker's architecture."};
  }
  Elf64_Half type = 0;
  Elf64_Half machine = 0;
  memcpy(&type, header + offsetof(Elf64_Ehdr, e_type), sizeof(type));
  memcpy(&machine, header + offsetof(Elf64_Ehdr, e_machine), sizeof(machine));
  if (NativeMachine() == EM_NONE || machine != NativeMachine()) {
    return {component, "wrong_architecture",
            "A bundled native library does not match this checker's architecture."};
  }
  if (type != ET_DYN || (native_class == ELFCLASS64 &&
                        count < static_cast<ssize_t>(sizeof(Elf64_Ehdr)))) {
    return {component, "invalid_library",
            "A bundled native library is not a valid shared ELF library."};
  }
  return Ok(component);
}

Check LoaderFailure(const char* component) {
  // Interpret only known categories. Never print dlerror(): it can contain
  // build paths, dependency search paths, or values from the process environment.
  const char* error = dlerror();
  const std::string detail = error == nullptr ? "" : error;
  if (detail.find("GLIBC_") != std::string::npos ||
      detail.find("GLIBCXX_") != std::string::npos ||
      detail.find("CXXABI_") != std::string::npos) {
    return {component, "incompatible_system_runtime",
            "The system C/C++ runtime is incompatible with a bundled native library."};
  }
  if (detail.find("undefined symbol") != std::string::npos) {
    return {component, "incompatible_library",
            "A native library has an unresolved symbol or incompatible dependency."};
  }
  if (detail.find("cannot open shared object file") != std::string::npos ||
      detail.find("No such file") != std::string::npos) {
    if (detail.find("libgtk-3.so") != std::string::npos) {
      return {component, "missing_gtk",
              "The GTK 3 system runtime required by the Linux application is unavailable."};
    }
    return {component, "missing_system_dependency",
            "A system native dependency required by a bundled library is unavailable."};
  }
  return {component, "invalid_library",
          "A bundled native library could not be loaded by this system."};
}

void* Load(const char* component, const std::string& path,
           std::vector<Check>* checks) {
  Check inspected = InspectElf(component, path);
  if (strcmp(inspected.status, "ok") != 0) {
    checks->push_back(inspected);
    return nullptr;
  }
  dlerror();
  void* library = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (library == nullptr) checks->push_back(LoaderFailure(component));
  return library;
}

bool HasSymbol(void* library, const char* name) {
  dlerror();
  void* symbol = dlsym(library, name);
  return dlerror() == nullptr && symbol != nullptr;
}

void CheckSymbols(const char* component, void* library,
                  const std::vector<const char*>& symbols,
                  std::vector<Check>* checks) {
  if (library == nullptr) return;
  for (const char* symbol : symbols) {
    if (!HasSymbol(library, symbol)) {
      checks->push_back({component, "missing_symbol",
                         "A bundled native library is missing a required public ABI symbol."});
      return;
    }
  }
  checks->push_back(Ok(component));
}

struct sqlite3;
struct sqlite3_stmt;

void CheckSqlite(void* library, std::vector<Check>* checks) {
  if (library == nullptr) return;
  const std::vector<const char*> symbols = {
      "sqlite3_open_v2", "sqlite3_prepare_v2", "sqlite3_step",
      "sqlite3_column_int64", "sqlite3_finalize", "sqlite3_close_v2"};
  for (const char* symbol : symbols) {
    if (!HasSymbol(library, symbol)) {
      checks->push_back({"sqlite", "missing_symbol",
                         "The bundled SQLite library is missing a required public ABI symbol."});
      return;
    }
  }
  const auto open_db = reinterpret_cast<int (*)(const char*, sqlite3**, int, const char*)>(
      dlsym(library, "sqlite3_open_v2"));
  const auto prepare = reinterpret_cast<int (*)(sqlite3*, const char*, int, sqlite3_stmt**, const char**)>(
      dlsym(library, "sqlite3_prepare_v2"));
  const auto step = reinterpret_cast<int (*)(sqlite3_stmt*)>(dlsym(library, "sqlite3_step"));
  const auto column = reinterpret_cast<int64_t (*)(sqlite3_stmt*, int)>(dlsym(library, "sqlite3_column_int64"));
  const auto finalize = reinterpret_cast<int (*)(sqlite3_stmt*)>(dlsym(library, "sqlite3_finalize"));
  const auto close_db = reinterpret_cast<int (*)(sqlite3*)>(dlsym(library, "sqlite3_close_v2"));
  sqlite3* database = nullptr;
  sqlite3_stmt* statement = nullptr;
  // READWRITE | CREATE | MEMORY | NOMUTEX: no file, HOME, or application data.
  bool ok = open_db(":memory:", &database, 0x00000002 | 0x00000004 |
                     0x00000080 | 0x00008000, nullptr) == 0 && database != nullptr;
  if (ok) {
    ok = prepare(database, "SELECT 40 + 2", -1, &statement, nullptr) == 0 &&
         statement != nullptr;
  }
  if (ok) ok = step(statement) == 100 && column(statement, 0) == 42 &&
               step(statement) == 101;
  if (statement != nullptr && finalize(statement) != 0) ok = false;
  if (database != nullptr && close_db(database) != 0) ok = false;
  checks->push_back(ok ? Ok("sqlite")
                      : Check{"sqlite", "query_failed",
                              "The bundled SQLite library could not complete an in-memory query."});
}

void Report(const std::vector<Check>& checks) {
  bool ok = true;
  for (const Check& check : checks) ok = ok && strcmp(check.status, "ok") == 0;
  if (json_output) {
    printf("{\"schema_version\":1,\"ok\":%s,\"status\":\"%s\",\"checks\":[",
           ok ? "true" : "false", ok ? "ok" : "failed");
    for (size_t index = 0; index < checks.size(); ++index) {
      const Check& check = checks[index];
      // These are compile-time strings, never user or loader supplied values.
      printf("%s{\"component\":\"%s\",\"status\":\"%s\",\"message\":\"%s\"}",
             index == 0 ? "" : ",", check.component, check.status, check.message);
    }
    printf("]}\n");
  } else if (ok) {
    printf("Runtime check passed: bundled native libraries and in-memory SQLite are available.\n");
  } else {
    for (const Check& check : checks) {
      if (strcmp(check.status, "ok") != 0) {
        fprintf(stderr, "Runtime check failed [%s/%s]: %s\n",
                check.component, check.status, check.message);
      }
    }
  }
}


// Only fixed vocabulary crosses the worker pipe. Native constructors execute in
// a child with silent standard streams; they cannot contaminate the report.
const char* const kComponents[] = {
    "bundle", "system_math", "file_selector", "flutter", "rust", "sqlite"};
const char* const kStatuses[] = {
    "ok", "missing_library", "unreadable_library", "invalid_library",
    "wrong_architecture", "incompatible_system_runtime", "incompatible_library",
    "missing_gtk", "missing_system_dependency", "missing_symbol", "query_failed"};
struct WireCheck {
  uint32_t component;
  uint32_t status;
};

template <size_t Count>
uint32_t VocabularyIndex(const char* value, const char* const (&words)[Count]) {
  for (uint32_t index = 0; index < Count; ++index) {
    if (strcmp(value, words[index]) == 0) return index;
  }
  return static_cast<uint32_t>(Count);
}

const char* Message(const char* component, const char* status) {
  if (strcmp(status, "ok") == 0) return "Native prerequisite is available.";
  if (strcmp(status, "missing_library") == 0 || strcmp(status, "unreadable_library") == 0)
    return "A required bundled native library is missing or unreadable.";
  if (strcmp(status, "wrong_architecture") == 0)
    return "A bundled native library does not match this checker's architecture.";
  if (strcmp(status, "incompatible_system_runtime") == 0)
    return "The system C/C++ runtime is incompatible with a bundled native library.";
  if (strcmp(status, "incompatible_library") == 0)
    return "A native library has an unresolved symbol or incompatible dependency.";
  if (strcmp(status, "missing_gtk") == 0)
    return "The GTK 3 system runtime required by the Linux application is unavailable.";
  if (strcmp(status, "missing_system_dependency") == 0)
    return strcmp(component, "system_math") == 0
        ? "The system math runtime required by SQLite is unavailable."
        : "A system native dependency required by a bundled library is unavailable.";
  if (strcmp(status, "missing_symbol") == 0)
    return strcmp(component, "sqlite") == 0
        ? "The bundled SQLite library is missing a required public ABI symbol."
        : "A bundled native library is missing a required public ABI symbol.";
  if (strcmp(status, "query_failed") == 0)
    return "The bundled SQLite library could not complete an in-memory query.";
  return "A bundled native library is not a valid shared ELF library.";
}

std::vector<Check> Probe(const std::string& root) {
  std::vector<Check> checks;
  // The supplied SQLite asset uses libm without a DT_NEEDED entry. The GTK
  // runner normally supplies it; preflight explicitly supplies the system libm.
  dlerror();
  void* math = dlopen("libm.so.6", RTLD_NOW | RTLD_GLOBAL);
  checks.push_back(math != nullptr
      ? Ok("system_math")
      : Check{"system_math", "missing_system_dependency",
              "The system math runtime required by SQLite is unavailable."});
  // Loading the plugin first checks its own relative dependency lookup. Loading
  // Flutter first would cache its SONAME and hide a broken plugin RUNPATH.
  void* selector = Load("file_selector", root + "/lib/libfile_selector_linux_plugin.so", &checks);
  CheckSymbols("file_selector", selector,
               {"file_selector_plugin_register_with_registrar"}, &checks);
  void* flutter = Load("flutter", root + "/lib/libflutter_linux_gtk.so", &checks);
  CheckSymbols("flutter", flutter, {"fl_engine_get_type"}, &checks);
  void* rust = Load("rust", root + "/lib/librust_lib_sync_lab.so", &checks);
  CheckSymbols("rust", rust, {
      "frbgen_sync_lab_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDocumentSession",
      "frbgen_sync_lab_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDocumentSession"}, &checks);
  void* sqlite = Load("sqlite", root + "/lib/libsqlite3.so", &checks);
  CheckSqlite(sqlite, &checks);
  return checks;
}

int Unavailable(const char* status, const char* message) {
  if (json_output) {
    printf("{\"schema_version\":1,\"ok\":false,\"status\":\"%s\",\"checks\":[]}\n", status);
  } else {
    fprintf(stderr, "Runtime check failed: %s\n", message);
  }
  return 1;
}

int Supervise(const std::string& root) {
  int channel[2];
  if (pipe(channel) != 0)
    return Unavailable("check_unavailable", "the native runtime check could not be initialized.");
  // A caller can have standard streams closed. Keep IPC out of the descriptors
  // the worker will replace with /dev/null.
  for (int& descriptor : channel) {
    if (descriptor <= STDERR_FILENO) {
      const int relocated = fcntl(descriptor, F_DUPFD_CLOEXEC, STDERR_FILENO + 1);
      if (relocated < 0) {
        close(channel[0]); close(channel[1]);
        return Unavailable("check_unavailable", "the native runtime check could not be initialized.");
      }
      close(descriptor);
      descriptor = relocated;
    }
  }
  const pid_t worker = fork();
  if (worker < 0) {
    close(channel[0]); close(channel[1]);
    return Unavailable("check_unavailable", "the native runtime check could not be initialized.");
  }
  if (worker == 0) {
    close(channel[0]);
    const struct rlimit no_core = {0, 0};
    if (setrlimit(RLIMIT_CORE, &no_core) != 0) _exit(1);
    const int silent = open("/dev/null", O_RDWR);
    if (silent < 0) _exit(1);
    for (int fd : {STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO}) {
      if (dup2(silent, fd) < 0) _exit(1);
    }
    if (silent > STDERR_FILENO) close(silent);
    const std::vector<Check> checks = Probe(root);
    if (checks.size() != 5) _exit(1);
    WireCheck result[5];
    for (size_t index = 0; index < checks.size(); ++index) {
      result[index] = {VocabularyIndex(checks[index].component, kComponents),
                       VocabularyIndex(checks[index].status, kStatuses)};
    }
    ssize_t written;
    do { written = write(channel[1], result, sizeof(result)); }
    while (written < 0 && errno == EINTR);
    // Avoid application/library finalizers and atexit callbacks altogether.
    _exit(written == static_cast<ssize_t>(sizeof(result)) ? 0 : 1);
  }
  close(channel[1]);
  WireCheck result[5] = {};
  size_t received = 0;
  int worker_status = 0;
  bool exited = false;
  bool timeout = false;
  const auto deadline = std::chrono::steady_clock::now() +
      std::chrono::seconds(kDeadlineSeconds);
  while (!exited) {
    const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
        deadline - std::chrono::steady_clock::now()).count();
    if (remaining <= 0) { timeout = true; break; }
    struct pollfd watched = {channel[0], POLLIN, 0};
    const int ready = poll(&watched, 1, static_cast<int>(remaining));
    if (ready < 0 && errno != EINTR) break;
    if (ready > 0 && received < sizeof(result)) {
      const ssize_t count = read(channel[0], reinterpret_cast<char*>(result) + received,
                                 sizeof(result) - received);
      if (count > 0) received += static_cast<size_t>(count);
      else if (count < 0 && errno != EINTR) break;
    }
    const pid_t reaped = waitpid(worker, &worker_status, WNOHANG);
    if (reaped == worker) exited = true;
    else if (reaped < 0 && errno != EINTR) break;
  }
  close(channel[0]);
  if (!exited) {
    kill(worker, SIGKILL);
    while (waitpid(worker, &worker_status, 0) < 0 && errno == EINTR) {}
  }
  if (timeout)
    return Unavailable("timeout", "native library checks exceeded 10 seconds.");
  if (!exited || !WIFEXITED(worker_status) || WEXITSTATUS(worker_status) != 0 ||
      received != sizeof(result)) {
    return Unavailable("native_library_error", "a native library could not execute safely.");
  }
  std::vector<Check> checks;
  for (uint32_t index = 0; index < 5; ++index) {
    if (result[index].component != index + 1 ||
        result[index].status >= sizeof(kStatuses) / sizeof(kStatuses[0])) {
      return Unavailable("native_library_error", "a native library could not execute safely.");
    }
    const char* component = kComponents[result[index].component];
    const char* status = kStatuses[result[index].status];
    checks.push_back({component, status, Message(component, status)});
  }
  Report(checks);
  for (const Check& check : checks) {
    if (strcmp(check.status, "ok") != 0) return 1;
  }
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  for (int index = 1; index < argc; ++index) {
    if (strcmp(argv[index], "--json") == 0) json_output = 1;
  }
  if (argc == 2 && strcmp(argv[1], "--help") == 0) {
    printf("Usage: vortice-runtime-check [--json]\n"
           "Check bundled Linux native libraries without starting the application.\n"
           "Exit codes: 0 ready; 1 runtime unavailable; 2 invalid arguments.\n");
    return 0;
  }
  if (!(argc == 1 || (argc == 2 && strcmp(argv[1], "--json") == 0))) {
    if (json_output) {
      printf("{\"schema_version\":1,\"ok\":false,\"status\":\"invalid_arguments\",\"checks\":[]}\n");
    } else {
      fprintf(stderr, "Usage: vortice-runtime-check [--json]\n");
    }
    return 2;
  }
  std::string root;
  if (!ExecutableRoot(&root)) {
    Report({{"bundle", "bundle_unavailable", "The native checker could not locate its bundle."}});
    return 1;
  }
  return Supervise(root);
}
