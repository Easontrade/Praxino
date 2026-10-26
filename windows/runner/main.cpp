#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kMutexName[] = L"Local\\Praxino.SingleInstance";
constexpr ULONG_PTR kCopyDataMagic = 0x50524158;

// Sends the second instance's command line to the already running window.
bool ForwardCommandLine(const std::vector<std::string>& arguments) {
  HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Praxino");
  if (existing == nullptr) {
    return false;
  }
  std::string payload;
  for (size_t i = 0; i < arguments.size(); ++i) {
    if (i != 0) {
      payload.push_back('\n');
    }
    payload += arguments[i];
  }
  COPYDATASTRUCT data = {};
  data.dwData = kCopyDataMagic;
  data.cbData = static_cast<DWORD>(payload.size());
  data.lpData = payload.data();
  return ::SendMessageW(existing, WM_COPYDATA, 0,
                        reinterpret_cast<LPARAM>(&data)) == TRUE;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  bool hidden = false;
#ifndef NDEBUG
  for (const auto& argument : command_line_arguments) {
    if (argument == "--hidden") {
      hidden = true;
    }
  }
#endif

  HANDLE mutex = ::CreateMutexW(nullptr, FALSE, kMutexName);
  if (mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Give the first instance a moment to finish creating its window.
    for (int attempt = 0; attempt < 20; ++attempt) {
      if (ForwardCommandLine(command_line_arguments)) {
        break;
      }
      ::Sleep(50);
    }
    ::CloseHandle(mutex);
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, hidden);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Praxino", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
