#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <algorithm>
#include <cstdint>
#include <limits>
#include <vector>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";
constexpr const wchar_t kWindowStateRegKey[] =
    L"Software\\loliSnatcher\\Window";

bool ReadRegistryDword(HKEY key, const wchar_t* name, DWORD* value) {
  DWORD size = sizeof(*value);
  DWORD type = 0;
  return RegQueryValueEx(key, name, nullptr, &type,
                         reinterpret_cast<BYTE*>(value), &size) ==
             ERROR_SUCCESS &&
         type == REG_DWORD;
}

void WriteRegistryDword(HKEY key, const wchar_t* name, LONG value) {
  const DWORD stored_value = static_cast<DWORD>(value);
  RegSetValueEx(key, name, 0, REG_DWORD,
                reinterpret_cast<const BYTE*>(&stored_value),
                sizeof(stored_value));
}

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Build a union so windows spanning displays (including mirrored displays)
// count each visible pixel once, excluding taskbars and gaps between monitors.
BOOL CALLBACK AddMonitorWorkArea(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  MONITORINFO info{sizeof(info)};
  if (!GetMonitorInfo(monitor, &info)) {
    return FALSE;
  }
  HRGN work_area = CreateRectRgnIndirect(&info.rcWork);
  if (work_area == nullptr) {
    return FALSE;
  }
  HRGN visible_region = reinterpret_cast<HRGN>(data);
  const int result = CombineRgn(visible_region, visible_region, work_area,
                                RGN_OR);
  DeleteObject(work_area);
  return result != ERROR;
}

bool IsAtLeastHalfVisible(const RECT& bounds) {
  HRGN visible_region = CreateRectRgn(0, 0, 0, 0);
  HRGN window_region = CreateRectRgnIndirect(&bounds);
  bool visible = false;
  if (visible_region != nullptr && window_region != nullptr &&
      EnumDisplayMonitors(nullptr, nullptr, AddMonitorWorkArea,
                          reinterpret_cast<LPARAM>(visible_region)) &&
      CombineRgn(visible_region, visible_region, window_region, RGN_AND) !=
          ERROR) {
    const DWORD data_size = GetRegionData(visible_region, 0, nullptr);
    if (data_size != 0) {
      std::vector<BYTE> buffer(data_size);
      auto data = reinterpret_cast<RGNDATA*>(buffer.data());
      if (GetRegionData(visible_region, data_size, data) != 0) {
        const auto rects = reinterpret_cast<const RECT*>(data->Buffer);
        int64_t visible_area = 0;
        for (DWORD i = 0; i < data->rdh.nCount; ++i) {
          visible_area +=
              (static_cast<int64_t>(rects[i].right) - rects[i].left) *
              (static_cast<int64_t>(rects[i].bottom) - rects[i].top);
        }
        const int64_t window_area =
            (static_cast<int64_t>(bounds.right) - bounds.left) *
            (static_cast<int64_t>(bounds.bottom) - bounds.top);
        visible = visible_area >= (window_area + 1) / 2;
      }
    }
  }
  if (window_region != nullptr) {
    DeleteObject(window_region);
  }
  if (visible_region != nullptr) {
    DeleteObject(visible_region);
  }
  return visible;
}

bool EnsureWindowVisible(RECT* bounds) {
  if (IsAtLeastHalfVisible(*bounds)) {
    return true;
  }
  HMONITOR monitor = MonitorFromRect(bounds, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{sizeof(info)};
  if (!GetMonitorInfo(monitor, &info)) {
    return false;
  }
  const RECT& work = info.rcWork;
  const LONG width = std::min(bounds->right - bounds->left,
                              work.right - work.left);
  const LONG height = std::min(bounds->bottom - bounds->top,
                               work.bottom - work.top);
  bounds->left = std::clamp(bounds->left, work.left, work.right - width);
  bounds->top = std::clamp(bounds->top, work.top, work.bottom - height);
  bounds->right = bounds->left + width;
  bounds->bottom = bounds->top + height;
  return true;
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      origin.x, origin.y, static_cast<int>(size.width),
      static_cast<int>(size.height),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_,
                    IsZoomed(window_handle_) ? SW_SHOWMAXIMIZED
                                             : SW_SHOWNORMAL);
}

void Win32Window::GetDefaultWindowState(Point* origin, Size* size) {
  constexpr int kDefaultOffset = 100;
  HMONITOR monitor = MonitorFromWindow(nullptr, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info{sizeof(monitor_info)};
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return;
  }

  const double scale_factor = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const RECT& bounds = monitor_info.rcWork;
  size->width = (bounds.right - bounds.left) / 2;
  size->height = (bounds.bottom - bounds.top) / 2;
  const int offset = Scale(kDefaultOffset, scale_factor);
  origin->x = bounds.left + std::min(offset, static_cast<int>(size->width));
  origin->y = bounds.top + std::min(offset, static_cast<int>(size->height));
}

void Win32Window::LoadSavedWindowState(Point* origin, Size* size,
                                       bool* maximized) {
  HKEY key = nullptr;
  if (RegOpenKeyEx(HKEY_CURRENT_USER, kWindowStateRegKey, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return;
  }

  DWORD left = 0;
  DWORD top = 0;
  DWORD right = 0;
  DWORD bottom = 0;
  DWORD saved_maximized = 0;
  const bool has_bounds =
      ReadRegistryDword(key, L"Left", &left) &&
      ReadRegistryDword(key, L"Top", &top) &&
      ReadRegistryDword(key, L"Right", &right) &&
      ReadRegistryDword(key, L"Bottom", &bottom);
  ReadRegistryDword(key, L"Maximized", &saved_maximized);
  RegCloseKey(key);

  if (!has_bounds) {
    return;
  }

  RECT saved_rect = {
      static_cast<LONG>(left),
      static_cast<LONG>(top),
      static_cast<LONG>(right),
      static_cast<LONG>(bottom),
  };
  const int64_t width = static_cast<int64_t>(saved_rect.right) - saved_rect.left;
  const int64_t height = static_cast<int64_t>(saved_rect.bottom) - saved_rect.top;
  if (width <= 0 || height <= 0 ||
      width > std::numeric_limits<int>::max() ||
      height > std::numeric_limits<int>::max()) {
    return;
  }

  if (!EnsureWindowVisible(&saved_rect)) {
    return;
  }

  // Persisted bounds and CreateWindow both use physical screen coordinates.
  // Dividing the desktop origin by DPI can select a different monitor at launch.
  origin->x = saved_rect.left;
  origin->y = saved_rect.top;
  size->width = saved_rect.right - saved_rect.left;
  size->height = saved_rect.bottom - saved_rect.top;
  *maximized = saved_maximized != 0;
}

void Win32Window::SaveWindowState() {
  WINDOWPLACEMENT placement{sizeof(placement)};
  if (!GetWindowPlacement(window_handle_, &placement)) {
    return;
  }

  const bool minimized = IsIconic(window_handle_) != FALSE;
  const bool maximized =
      IsZoomed(window_handle_) || placement.showCmd == SW_SHOWMAXIMIZED ||
      (minimized && (placement.flags & WPF_RESTORETOMAXIMIZED) != 0);
  RECT bounds = placement.rcNormalPosition;
  if (!maximized && !minimized) {
    // GetWindowRect uses screen coordinates, unlike rcNormalPosition which
    // uses workspace coordinates and can be offset by the taskbar.
    if (!GetWindowRect(window_handle_, &bounds)) {
      return;
    }
  } else {
    HMONITOR monitor =
        MonitorFromWindow(window_handle_, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitor_info{sizeof(monitor_info)};
    if (GetMonitorInfo(monitor, &monitor_info)) {
      OffsetRect(&bounds,
                 monitor_info.rcWork.left - monitor_info.rcMonitor.left,
                 monitor_info.rcWork.top - monitor_info.rcMonitor.top);
    }
  }

  HKEY key = nullptr;
  if (RegCreateKeyEx(HKEY_CURRENT_USER, kWindowStateRegKey, 0, nullptr, 0,
                     KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }

  WriteRegistryDword(key, L"Left", bounds.left);
  WriteRegistryDword(key, L"Top", bounds.top);
  WriteRegistryDword(key, L"Right", bounds.right);
  WriteRegistryDword(key, L"Bottom", bounds.bottom);
  WriteRegistryDword(key, L"Maximized", maximized);
  RegCloseKey(key);
}

void Win32Window::ResetWindowState() {
  Point origin(100, 100);
  Size size(960, 540);
  GetDefaultWindowState(&origin, &size);

  ShowWindow(window_handle_, SW_RESTORE);
  SetWindowPos(window_handle_, nullptr, origin.x, origin.y,
               static_cast<int>(size.width), static_cast<int>(size.height),
               SWP_NOZORDER | SWP_NOACTIVATE);
  SaveWindowState();
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE:
      SaveWindowState();
      break;

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
