#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <libgen.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <mach-o/dyld.h>
#include <limits.h>

// Returns 1 if something is listening on 127.0.0.1:port (TCP connect
// succeeds within ~500ms), 0 otherwise. Used to distinguish "no server
// running, fork a new BEAM" from "server is hung, kill it first".
static int port_bound(int port) {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return 0;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    int flags = fcntl(sock, F_GETFL, 0);
    fcntl(sock, F_SETFL, flags | O_NONBLOCK);

    int bound = 0;
    int rc = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
    if (rc == 0) {
        bound = 1;
    } else if (errno == EINPROGRESS) {
        fd_set wfds;
        FD_ZERO(&wfds);
        FD_SET(sock, &wfds);
        struct timeval tv = {0, 500000};
        if (select(sock + 1, NULL, &wfds, NULL, &tv) > 0) {
            int err = 0;
            socklen_t elen = sizeof(err);
            if (getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &elen) == 0 && err == 0) {
                bound = 1;
            }
        }
    }
    close(sock);
    return bound;
}

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    char exec_path[PATH_MAX];
    uint32_t size = sizeof(exec_path);
    if (_NSGetExecutablePath(exec_path, &size) != 0) {
        fprintf(stderr, "launcher: couldn't resolve executable path\n");
        return 1;
    }

    // exec_path = .../StockPlan.app/Contents/MacOS/StockPlan
    char macos_buf[PATH_MAX];
    strncpy(macos_buf, exec_path, sizeof(macos_buf) - 1);
    macos_buf[sizeof(macos_buf) - 1] = '\0';
    char *macos_dir = dirname(macos_buf);

    char contents_buf[PATH_MAX];
    strncpy(contents_buf, macos_dir, sizeof(contents_buf) - 1);
    contents_buf[sizeof(contents_buf) - 1] = '\0';
    char *contents_dir = dirname(contents_buf);

    char rel_dir[PATH_MAX];
    snprintf(rel_dir, sizeof(rel_dir), "%s/Resources/release", contents_dir);

    char cmd[PATH_MAX * 2];
    snprintf(cmd, sizeof(cmd),
             "/usr/bin/xattr -cr \"%s\" 2>/dev/null", rel_dir);
    system(cmd);
    snprintf(cmd, sizeof(cmd),
             "/bin/chmod -R +x \"%s/bin\" \"%s\"/erts-*/bin 2>/dev/null",
             rel_dir, rel_dir);
    system(cmd);

    if (system("/usr/bin/curl -sf --max-time 1 http://localhost:4002/ >/dev/null 2>&1") == 0) {
        system("/usr/bin/open http://localhost:4002");
        return 0;
    }

    // Curl failed. If the port is bound, a previous BEAM is hung — kill it
    // and start fresh. SQLite + Ecto's transactional model means in-flight
    // writes get rolled back cleanly; migrations are idempotent. Scope the
    // pkill to our exact bundle path so we never touch a dev-mode BEAM or a
    // BEAM from some other Erlang app.
    if (port_bound(4002)) {
        char kill_cmd[PATH_MAX * 2];
        snprintf(kill_cmd, sizeof(kill_cmd),
                 "/usr/bin/pkill -9 -f \"%s/erts\" 2>/dev/null", rel_dir);
        system(kill_cmd);
        sleep(2);
    }

    char bin_path[PATH_MAX];
    snprintf(bin_path, sizeof(bin_path), "%s/bin/stock_plan", rel_dir);

    // Fork-and-detach so the launcher process exits cleanly. If we exec'd
    // into the BEAM directly, macOS would treat the BEAM as the .app's main
    // process — and any subsequent double-click on the .app icon would try
    // to activate it via Apple Events, hang for 30s, and surface the
    // "application is not responding" error. Detaching lets each launch
    // start fresh: the launcher runs, finds the server already up, opens
    // the browser, exits.
    pid_t pid = fork();
    if (pid < 0) {
        perror("launcher: fork");
        return 1;
    }

    if (pid == 0) {
        // Child: detach from the launcher's session and replace with BEAM.
        if (setsid() < 0) _exit(1);

        int devnull = open("/dev/null", O_RDWR);
        if (devnull >= 0) {
            dup2(devnull, STDIN_FILENO);
            dup2(devnull, STDOUT_FILENO);
            dup2(devnull, STDERR_FILENO);
            if (devnull > STDERR_FILENO) close(devnull);
        }

        execl(bin_path, "stock_plan", "start", (char *)NULL);
        _exit(1);
    }

    // Parent: poll for the server, then open the browser and exit.
    for (int i = 0; i < 20; i++) {
        sleep(1);
        if (system("/usr/bin/curl -sf --max-time 1 http://localhost:4002/ >/dev/null 2>&1") == 0) {
            break;
        }
    }

    system("/usr/bin/open http://localhost:4002");
    return 0;
}
