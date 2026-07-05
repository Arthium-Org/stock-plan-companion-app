/*
 * Native Windows launcher for Stock Plan Manager.
 *
 * Mirrors the macOS launcher.c behavior:
 *   1. If a server is already listening on http://localhost:4002, just open
 *      the browser to it and exit.
 *   2. Otherwise start `release\bin\stock_plan.bat start` as a detached
 *      background process, wait briefly for the BEAM to come up, then open
 *      the browser.
 *
 * Compiled with: cl /O2 /Fe:StockPlan.exe launcher_win.c /link winhttp.lib
 *                shell32.lib /SUBSYSTEM:WINDOWS
 */

#define _CRT_SECURE_NO_WARNINGS
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <winhttp.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")

/* Returns 1 if something is listening on 127.0.0.1:port, 0 otherwise.
 * Used to distinguish "no server running, fork a new BEAM" from "server
 * is hung, kill it first". */
static int port_bound(int port) {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return 0;

    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET) { WSACleanup(); return 0; }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((u_short)port);
    InetPtonA(AF_INET, "127.0.0.1", &addr.sin_addr);

    u_long nonblock = 1;
    ioctlsocket(s, FIONBIO, &nonblock);

    int bound = 0;
    int rc = connect(s, (struct sockaddr *)&addr, sizeof(addr));
    if (rc == 0) {
        bound = 1;
    } else if (WSAGetLastError() == WSAEWOULDBLOCK) {
        fd_set wfds;
        FD_ZERO(&wfds);
        FD_SET(s, &wfds);
        struct timeval tv = {0, 500000};
        if (select(0, NULL, &wfds, NULL, &tv) > 0) {
            int err = 0;
            int elen = sizeof(err);
            if (getsockopt(s, SOL_SOCKET, SO_ERROR, (char *)&err, &elen) == 0 && err == 0) {
                bound = 1;
            }
        }
    }
    closesocket(s);
    WSACleanup();
    return bound;
}

static int server_running(void) {
    int running = 0;
    HINTERNET hSession = WinHttpOpen(L"StockPlan/1.0",
                                     WINHTTP_ACCESS_TYPE_NO_PROXY,
                                     WINHTTP_NO_PROXY_NAME,
                                     WINHTTP_NO_PROXY_BYPASS, 0);
    if (!hSession) return 0;

    DWORD timeout = 1000;
    WinHttpSetTimeouts(hSession, timeout, timeout, timeout, timeout);

    HINTERNET hConnect = WinHttpConnect(hSession, L"127.0.0.1", 4002, 0);
    if (!hConnect) goto cleanup_session;

    HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", L"/",
                                            NULL, WINHTTP_NO_REFERER,
                                            WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
    if (!hRequest) goto cleanup_connect;

    if (WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                           WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
        WinHttpReceiveResponse(hRequest, NULL)) {
        running = 1;
    }

    WinHttpCloseHandle(hRequest);
cleanup_connect:
    WinHttpCloseHandle(hConnect);
cleanup_session:
    WinHttpCloseHandle(hSession);
    return running;
}

/* ---- Boot splash --------------------------------------------------------
 * A small top-most window shown while the BEAM cold-boots. Without it the
 * launcher is a windowless process: the user clicks "Launch" / the desktop
 * icon and stares at nothing for up to 20s. Owning a real foreground window
 * also lets us hand foreground to the browser (see AllowSetForegroundWindow
 * at the open-browser calls) so it doesn't open behind the installer. */

static const char *SPLASH_LINE1 = "Starting Stock Plan Manager...";
static const char *SPLASH_LINE2 = "This will open in your browser in a moment.";

static LRESULT CALLBACK splash_wndproc(HWND hWnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_PAINT) {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hWnd, &ps);
        RECT rc;
        GetClientRect(hWnd, &rc);
        FillRect(hdc, &rc, (HBRUSH)(COLOR_WINDOW + 1));
        SetBkMode(hdc, TRANSPARENT);
        HFONT old = (HFONT)SelectObject(hdc, (HFONT)GetStockObject(DEFAULT_GUI_FONT));

        RECT r1 = rc; r1.top += 36;
        SetTextColor(hdc, RGB(20, 20, 20));
        DrawTextA(hdc, SPLASH_LINE1, -1, &r1, DT_CENTER | DT_TOP | DT_SINGLELINE);

        RECT r2 = rc; r2.top += 66;
        SetTextColor(hdc, RGB(90, 90, 90));
        DrawTextA(hdc, SPLASH_LINE2, -1, &r2, DT_CENTER | DT_TOP | DT_SINGLELINE);

        SelectObject(hdc, old);
        EndPaint(hWnd, &ps);
        return 0;
    }
    return DefWindowProcA(hWnd, msg, wp, lp);
}

static HWND splash_show(HINSTANCE hInst) {
    WNDCLASSA wc;
    memset(&wc, 0, sizeof(wc));
    wc.lpfnWndProc = splash_wndproc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = "StockPlanSplash";
    RegisterClassA(&wc);

    int w = 400, h = 150;
    int x = (GetSystemMetrics(SM_CXSCREEN) - w) / 2;
    int y = (GetSystemMetrics(SM_CYSCREEN) - h) / 2;

    HWND hWnd = CreateWindowExA(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
        "StockPlanSplash", "Stock Plan Manager",
        WS_POPUP | WS_BORDER,
        x, y, w, h, NULL, NULL, hInst, NULL);
    if (hWnd) {
        ShowWindow(hWnd, SW_SHOW);
        SetForegroundWindow(hWnd);
        UpdateWindow(hWnd);
    }
    return hWnd;
}

/* Drain pending messages so the splash paints and stays responsive. */
static void splash_pump(void) {
    MSG msg;
    while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }
}

/* Open the app in the default browser, granting foreground rights first so the
 * browser window comes to the front instead of opening behind the installer. */
static void open_browser(void) {
    AllowSetForegroundWindow(ASFW_ANY);
    ShellExecuteA(NULL, "open", "http://localhost:4002", NULL, NULL, SW_SHOWNORMAL);
}

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR lpCmd, int nShow) {
    (void)hPrev; (void)lpCmd; (void)nShow;

    char exe_path[MAX_PATH];
    if (GetModuleFileNameA(NULL, exe_path, MAX_PATH) == 0) {
        MessageBoxA(NULL, "Could not resolve own path", "Stock Plan Manager", MB_ICONERROR);
        return 1;
    }

    /* Strip the trailing \StockPlan.exe to get the install dir. */
    char *last = strrchr(exe_path, '\\');
    if (last) *last = '\0';

    char bat_path[MAX_PATH];
    snprintf(bat_path, MAX_PATH, "%s\\release\\bin\\stock_plan.bat", exe_path);

    if (server_running()) {
        open_browser();
        return 0;
    }

    /* Cold start: show the splash immediately so there's instant feedback
     * while the BEAM boots, and so we own a foreground window to hand off to
     * the browser at the end. */
    HWND splash = splash_show(hInst);
    splash_pump();

    /* HTTP didn't respond. If the port is bound, a previous BEAM is hung —
     * kill it and start fresh. SQLite + Ecto's transactional model means
     * in-flight writes get rolled back cleanly; migrations are idempotent. */
    if (port_bound(4002)) {
        system("taskkill /F /IM erl.exe /T >NUL 2>NUL");
        system("taskkill /F /IM erlsrv.exe /T >NUL 2>NUL");
        splash_pump();
        Sleep(2000);
    }

    /* Launch the BEAM in its own hidden console so closing this launcher
     * process doesn't kill the server. CREATE_NO_WINDOW gives the child a
     * private, non-displayed console — erl.exe needs a console to set up its
     * standard I/O, so DETACHED_PROCESS (no console at all) makes it exit
     * immediately. The two flags are mutually exclusive; use only the former. */
    char cmd_line[MAX_PATH * 2];
    snprintf(cmd_line, sizeof(cmd_line), "cmd.exe /C \"\"%s\" start\"", bat_path);

    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    memset(&pi, 0, sizeof(pi));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;

    BOOL ok = CreateProcessA(NULL, cmd_line, NULL, NULL, FALSE,
                             CREATE_NO_WINDOW,
                             NULL, exe_path, &si, &pi);
    if (!ok) {
        if (splash) DestroyWindow(splash);
        MessageBoxA(NULL, "Failed to start Stock Plan Manager", "Stock Plan Manager", MB_ICONERROR);
        return 1;
    }
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    /* Poll for the server to come up — up to ~20 seconds. Pump the splash
     * every 200ms so it stays painted and responsive; probe the server once
     * a second. */
    for (int i = 0; i < 20; i++) {
        for (int j = 0; j < 5; j++) {
            splash_pump();
            Sleep(200);
        }
        if (server_running()) break;
    }

    open_browser();
    if (splash) DestroyWindow(splash);
    return 0;
}
