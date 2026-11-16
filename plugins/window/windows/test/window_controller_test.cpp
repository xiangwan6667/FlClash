#include "window_controller.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

void Check(bool condition, const char* message) {
  if (!condition) {
    std::cerr << message << '\n';
    std::exit(EXIT_FAILURE);
  }
}

}  // namespace

int main() {
  std::vector<std::string> events;
  window::WindowController controller(
      [&events](const std::string& event) { events.push_back(event); });
  controller.SetPreventClose(true);

  const LPARAM shutdown_reasons[] = {
      ENDSESSION_CLOSEAPP,
      ENDSESSION_CLOSEAPP | ENDSESSION_CRITICAL,
      static_cast<LPARAM>(ENDSESSION_LOGOFF),
      0,
  };
  for (const LPARAM reason : shutdown_reasons) {
    events.clear();
    Check(controller.HandleWindowMessage(nullptr, WM_QUERYENDSESSION, 0,
                                         reason) == TRUE,
          "Session shutdown must be accepted even with preventClose enabled");
    Check(events.empty(), "A shutdown query must not start cleanup");

    Check(controller.HandleWindowMessage(nullptr, WM_ENDSESSION, FALSE,
                                         reason) == 0,
          "A cancelled shutdown must be handled");
    Check(events.empty(), "A cancelled shutdown must keep the app running");

    Check(controller.HandleWindowMessage(nullptr, WM_ENDSESSION, TRUE,
                                         reason) == 0,
          "A confirmed shutdown must be handled");
    Check(events == std::vector<std::string>{"should-terminate"},
          "A confirmed shutdown must request full application cleanup");
  }

  events.clear();
  Check(controller.HandleWindowMessage(nullptr, WM_CLOSE, 0, 0) == -1,
        "Ordinary close must still respect preventClose");
  Check(events == std::vector<std::string>{"close"},
        "Ordinary close must retain its dedicated event");

  events.clear();
  controller.SetPreventClose(false);
  Check(!controller.HandleWindowMessage(nullptr, WM_CLOSE, 0, 0).has_value(),
        "Unprevented close must fall through to the runner");
  Check(events == std::vector<std::string>{"close"},
        "Unprevented close must still notify Dart");

  std::cout << "Window controller shutdown tests passed\n";
  return EXIT_SUCCESS;
}
