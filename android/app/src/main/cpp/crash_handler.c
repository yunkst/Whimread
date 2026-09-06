// Native crash signal handler —— Android SIGSEGV/SIGABRT 等崩溃捕获
//
// 设计目标：进程被 OS kill 之前，把崩溃信息（信号号、fault addr、tid、
// 时间戳、backtrace 地址、/proc/self/maps）写到 filesDir/crash/crash_<tid>_<ts>.txt，
// 供下次启动时 Flutter 侧读取并引导用户提 GitHub issue。
//
// maps 用于符号化裸 PC：11 帧裸 PC 减去对应 .so 的加载基址后，
// 可用 NDK addr2line / llvm-symbolizer 还原出函数名，定位崩溃落在
// ORT 内部 / NNAPI 驱动 / 插件 FFI 哪一层。
//
// ★ async-signal-safe 约束（POSIX）：signal handler 里只能调用
//   open/write/close/syscall/clock_gettime 等明确列为 async-signal-safe
//   的函数。禁止 malloc/stdio/snprintf/JNI/锁。
//   - 字符串拼接：栈上 buffer + 手写 u64→hex/dec，不用 snprintf
//   - 栈回溯：_Unwind_Backtrace（Android Bionic 不含 execinfo.h/backtrace()）
//   - 独立信号栈 sigaltstack：防栈溢出导致的二次崩溃
//
// handler 末尾恢复默认信号处理并 raise，让进程按系统默认方式死亡
// （Android 仍会生成 tombstone，不受影响）。
#include <jni.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>
#include <stdint.h>
#include <stddef.h>
#include <sys/syscall.h>
#include <unwind.h>

#define CRASH_DUMP_DIR_MAX 256
#define CRASH_BT_MAX 64
// 独立信号栈大小。Bionic 的 SIGSTKSZ 在不同版本可能是常量也可能是运行时
// 值，这里用固定 32KB 规避编译期不确定性（足够展开栈）。
#define CRASH_ALT_STACK_SIZE 32768

// install 时写一次，handler 内只读 —— 线程安全。
static char g_dump_dir[CRASH_DUMP_DIR_MAX];
static int g_dump_dir_len = 0;

// 独立信号栈（进程级，避免在溢出的栈上跑 handler）。
static char g_alt_stack[CRASH_ALT_STACK_SIZE];

// 各信号保留旧 handler，handler 末尾恢复。
static struct sigaction g_prev[32];

// ---- async-signal-safe 整数 → 字符串 ----

static int u64_to_hex(uint64_t v, char *buf) {
    char tmp[16];
    int n = 0;
    if (v == 0) {
        buf[0] = '0';
        return 1;
    }
    while (v > 0 && n < 16) {
        const int d = (int)(v & 0xf);
        tmp[n++] = (d < 10) ? (char)('0' + d) : (char)('a' + d - 10);
        v >>= 4;
    }
    for (int i = 0; i < n; i++) buf[i] = tmp[n - 1 - i];
    return n;
}

static int u64_to_dec(uint64_t v, char *buf) {
    char tmp[20];
    int n = 0;
    if (v == 0) {
        buf[0] = '0';
        return 1;
    }
    while (v > 0 && n < 20) {
        tmp[n++] = (char)('0' + (int)(v % 10));
        v /= 10;
    }
    for (int i = 0; i < n; i++) buf[i] = tmp[n - 1 - i];
    return n;
}

// ---- write 包装（循环写完，处理 EINTR / 部分写） ----

static void write_all(int fd, const char *s, int len) {
    int off = 0;
    while (off < len) {
        const ssize_t w = write(fd, s + off, (size_t)(len - off));
        if (w <= 0) break;
        off += (int)w;
    }
}

static void write_str(int fd, const char *s) {
    write_all(fd, s, (int)strlen(s));
}

// ---- _Unwind_Backtrace（libgcc/libunwind 提供，NDK 默认链接） ----

struct bt_state {
    void **addrs;
    int max;
    int count;
};

static _Unwind_Reason_Code unwind_cb(struct _Unwind_Context *ctx, void *arg) {
    struct bt_state *const st = (struct bt_state *)arg;
    if (st->count >= st->max) return _URC_END_OF_STACK;
    st->addrs[st->count++] = (void *)(uintptr_t)_Unwind_GetIP(ctx);
    return _URC_NO_REASON;
}

static const char *signame(int signo) {
    switch (signo) {
        case SIGSEGV: return "SIGSEGV";
        case SIGABRT: return "SIGABRT";
        case SIGBUS:  return "SIGBUS";
        case SIGILL:  return "SIGILL";
        case SIGFPE:  return "SIGFPE";
        case SIGTRAP: return "SIGTRAP";
        default:      return "UNKNOWN";
    }
}

// ---- 核心 signal handler ----
//
// 注意：此函数运行在崩溃线程 + 可能已损坏的栈上（由 sigaltstack 兜底），
// 全程 async-signal-safe。
static void crash_handler(int signo, siginfo_t *info, void *ucontext) {
    (void)ucontext;

    // dump_dir 未初始化时跳过写文件，直接 raise 让进程死亡。
    if (g_dump_dir_len > 0) {
        // 组装路径：<dump_dir>/crash_<tid>_<ts>.txt
        char path[CRASH_DUMP_DIR_MAX + 64];
        int off = 0;
        memcpy(path, g_dump_dir, (size_t)g_dump_dir_len);
        off = g_dump_dir_len;
        path[off++] = '/';

        const char *prefix = "crash_";
        memcpy(path + off, prefix, 6);
        off += 6;

        const long tid = (long)syscall(SYS_gettid);
        off += u64_to_dec((uint64_t)tid, path + off);
        path[off++] = '_';

        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        off += u64_to_dec((uint64_t)ts.tv_sec, path + off);

        memcpy(path + off, ".txt", 4);
        off += 4;
        path[off] = '\0';

        const int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd >= 0) {
            char buf[64];
            int len;

            write_str(fd, "=== NOVEL_CRASH_DUMP v1 ===\n");

            // signal:11 (SIGSEGV)
            write_str(fd, "signal:");
            len = u64_to_dec((uint64_t)signo, buf);
            write_all(fd, buf, len);
            write_str(fd, " (");
            write_str(fd, signame(signo));
            write_str(fd, ")\n");

            // fault_addr:0x...
            write_str(fd, "fault_addr:0x");
            len = u64_to_hex((uint64_t)(uintptr_t)(info ? info->si_addr : NULL), buf);
            write_all(fd, buf, len);
            write_str(fd, "\n");

            // tid:<gettid>
            write_str(fd, "tid:");
            len = u64_to_dec((uint64_t)tid, buf);
            write_all(fd, buf, len);
            write_str(fd, "\n");

            // timestamp:<epoch seconds>
            write_str(fd, "timestamp:");
            len = u64_to_dec((uint64_t)ts.tv_sec, buf);
            write_all(fd, buf, len);
            write_str(fd, "\n");

            // backtrace（PC 地址数组）
            write_str(fd, "backtrace:\n");
            void *addrs[CRASH_BT_MAX];
            struct bt_state st = { .addrs = addrs, .max = CRASH_BT_MAX, .count = 0 };
            _Unwind_Backtrace(unwind_cb, &st);

            for (int i = 0; i < st.count; i++) {
                write_str(fd, "  #");
                len = u64_to_dec((uint64_t)i, buf);
                write_all(fd, buf, len);
                write_str(fd, " pc 0x");
                len = u64_to_hex((uint64_t)(uintptr_t)addrs[i], buf);
                write_all(fd, buf, len);
                write_str(fd, "\n");
            }

            // ---- /proc/self/maps 输出（只保留含 ".so" 的行）----
            //
            // 目的：拿到各 .so 的加载基址（如 79c3e4d000-79c4100000 r--p ...
            // libonnxruntime.so）。backtrace 里只有裸 PC，减去对应库的基址后可用
            // addr2line/llvm-symbolizer 还原出函数名，定位崩溃落在 ORT 内部 /
            // NNAPI 驱动 / 插件 FFI 哪一层。
            //
            // ★ 只保留含 ".so" 的行：/proc/self/maps 上 Android 进程 maps 通常
            // 几百 KB，绝大多数是 [anon:partition_alloc] / [anon:scudo:*] /
            // /dmabuf:* / /kgsl-3d0 / boot-*.oat 等"噪声行"，真正需要看的 .so 行
            // 只有几十条、几 KB。若全量输出，96KB 上限会被噪声塞满，关键 .so
            // 基址（特别是高地址段的 libonnxruntime.so / libflutter.so）被截断
            // 丢失。改成按行过滤只写 ".so" 行后，几十行 .so 总计几 KB，上限绰绰
            // 有余，所有 .so 基址必现。
            //
            // ★ 严格 async-signal-safe：open + 循环 read + write，无 malloc/stdio。
            // 行缓冲 line_buf 在栈上，逐字符扫描跨块边界（残留 prefix 带到下一块
            // 续扫）。
            write_str(fd, "=== maps (.so only) ===\n");
            const int maps_fd = open("/proc/self/maps", O_RDONLY);
            if (maps_fd >= 0) {
                char maps_buf[8192];
                char line_buf[512];   // 单行缓冲，maps 行极少超 200 字符
                int line_len = 0;     // line_buf 当前已累积长度（跨块续接）
                const char dot_so[4] = {'.', 's', 'o', '\0'};
                for (;;) {
                    const ssize_t r = read(maps_fd, maps_buf, sizeof(maps_buf));
                    if (r <= 0) break; // EOF 或出错
                    for (ssize_t i = 0; i < r; i++) {
                        const char c = maps_buf[i];
                        if (line_len < (int)sizeof(line_buf) - 1) {
                            line_buf[line_len++] = c;
                        } else {
                            // 行超长，截断：丢弃本行剩余直到换行
                            line_len = (int)sizeof(line_buf) - 1;
                        }
                        if (c == '\n') {
                            line_buf[line_len] = '\0';
                            // 仅当行含 ".so" 才输出（避开 anon/dmabuf/oat/kgsl 噪声）
                            // 简单线性扫描，async-signal-safe
                            int has_so = 0;
                            for (int j = 0; j + 2 < line_len; j++) {
                                if (line_buf[j] == dot_so[0] &&
                                    line_buf[j+1] == dot_so[1] &&
                                    line_buf[j+2] == dot_so[2]) {
                                    has_so = 1;
                                    break;
                                }
                            }
                            if (has_so) {
                                write_all(fd, line_buf, line_len);
                            }
                            line_len = 0;
                        }
                    }
                }
                // flush 最后一行（无尾换行的兜底）
                if (line_len > 0) {
                    line_buf[line_len] = '\0';
                    int has_so = 0;
                    for (int j = 0; j + 3 < line_len; j++) {
                        if (line_buf[j] == dot_so[0] &&
                            line_buf[j+1] == dot_so[1] &&
                            line_buf[j+2] == dot_so[2]) {
                            has_so = 1;
                            break;
                        }
                    }
                    if (has_so) {
                        write_all(fd, line_buf, line_len);
                        write_str(fd, "\n");
                    }
                }
                close(maps_fd);
            } else {
                write_str(fd, "(failed to open /proc/self/maps)\n");
            }

            write_str(fd, "=== END ===\n");
            close(fd);
        }
    }

    // 恢复该信号的默认 handler，re-raise 让进程按系统默认方式死亡
    // （Android 仍会生成 tombstone；本 handler 不改变 OS 的崩溃善后行为）。
    if (signo > 0 && signo < 32) {
        sigaction(signo, &g_prev[signo], NULL);
    }
    raise(signo);
}

static void install_signal(int signo) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = crash_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigaction(signo, &sa, &g_prev[signo]);
}

// ---- JNI 入口：Kotlin CrashReporter.nativeInstall(dumpDir) 调用 ----
//
// 包名 com.example.novel_app 中的下划线按 JNI 规则编码为 _1。
JNIEXPORT void JNICALL
Java_com_example_novel_1app_CrashReporter_nativeInstall(
    JNIEnv *env, jclass clazz, jstring dumpDir) {
    (void)clazz;
    if (dumpDir == NULL) return;

    const char *str = (*env)->GetStringUTFChars(env, dumpDir, NULL);
    if (str == NULL) return;
    size_t len = strlen(str);
    if (len >= CRASH_DUMP_DIR_MAX) len = CRASH_DUMP_DIR_MAX - 1;
    memcpy(g_dump_dir, str, len);
    g_dump_dir[len] = '\0';
    g_dump_dir_len = (int)len;
    (*env)->ReleaseStringUTFChars(env, dumpDir, str);

    // 独立信号栈：handler 跑在它上面，避免栈溢出导致 handler 二次崩溃。
    stack_t ss;
    ss.ss_sp = g_alt_stack;
    ss.ss_size = CRASH_ALT_STACK_SIZE;
    ss.ss_flags = 0;
    sigaltstack(&ss, NULL);

    install_signal(SIGSEGV);
    install_signal(SIGABRT);
    install_signal(SIGBUS);
    install_signal(SIGILL);
    install_signal(SIGFPE);
    install_signal(SIGTRAP);
}
