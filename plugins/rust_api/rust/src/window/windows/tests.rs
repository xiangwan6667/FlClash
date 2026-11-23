use super::*;
use windows_sys::Win32::UI::WindowsAndMessaging::{WM_ENDSESSION, WM_QUERYENDSESSION};

fn signals() -> Vec<WindowSignal> {
    crate::window::TEST_SIGNALS.with(|signals| std::mem::take(&mut *signals.borrow_mut()))
}

#[test]
fn confirmed_session_shutdown_requests_full_exit() {
    STATE.with(|state| {
        state.relaunch_allowed.set(true);
        state.prevent_close.set(true);
        for reason in [0, 1, 3, 0x8000_0000u32 as LPARAM] {
            signals();
            assert_eq!(
                handle_message(state, null_mut(), WM_QUERYENDSESSION, 0, reason),
                Some(1)
            );
            assert!(signals().is_empty());
            assert_eq!(
                handle_message(state, null_mut(), WM_ENDSESSION, 0, reason),
                Some(0)
            );
            assert!(signals().is_empty());
            assert_eq!(
                handle_message(state, null_mut(), WM_ENDSESSION, 1, reason),
                Some(0)
            );
            assert_eq!(signals(), vec![WindowSignal::ShouldTerminate]);
        }
        assert_eq!(handle_message(state, null_mut(), WM_CLOSE, 0, 0), Some(-1));
        assert_eq!(signals(), vec![WindowSignal::Close]);
        state.prevent_close.set(false);
        assert_eq!(handle_message(state, null_mut(), WM_CLOSE, 0, 0), None);
        assert_eq!(signals(), vec![WindowSignal::Close]);
    });
}
