use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let window = app.get_webview_window("notch").expect("notch window missing");
            #[cfg(target_os = "macos")]
            {
                configure_macos_window(&window);
                let w = window.clone();
                // Re-apply collection behavior + level whenever macOS touches
                // the window (focus, moves, space transitions can reset it).
                window.on_window_event(move |_| apply_window_flags(&w));
            }
            window.show().ok();
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

// NSWindowCollectionBehavior:
// CanJoinAllSpaces (1<<0) | Stationary (1<<4) | IgnoresCycle (1<<6) |
// FullScreenAuxiliary (1<<8)
#[cfg(target_os = "macos")]
const BEHAVIOR: u64 = (1 << 0) | (1 << 4) | (1 << 6) | (1 << 8);
// NSScreenSaverWindowLevel — above fullscreen apps and the menu bar.
#[cfg(target_os = "macos")]
const LEVEL: i64 = 1000;

#[cfg(target_os = "macos")]
fn apply_window_flags(window: &tauri::WebviewWindow) {
    use cocoa::base::id;
    use objc::{msg_send, sel, sel_impl};
    let Ok(ns_window_ptr) = window.ns_window() else { return };
    let ns_window = ns_window_ptr as id;
    unsafe {
        let _: () = msg_send![ns_window, setLevel: LEVEL];
        let _: () = msg_send![ns_window, setCollectionBehavior: BEHAVIOR];
    }
}

#[cfg(target_os = "macos")]
fn configure_macos_window(window: &tauri::WebviewWindow) {
    use cocoa::appkit::{NSApp, NSApplication, NSApplicationActivationPolicy, NSScreen, NSWindow};
    use cocoa::base::{id, nil};
    use cocoa::foundation::{NSPoint, NSRect};
    use objc::runtime::{Class, Object};
    use objc::{msg_send, sel, sel_impl};

    unsafe {
        // Accessory policy: no Dock icon, no Cmd+Tab. Required for the window
        // to cross into fullscreen Spaces via fullScreenAuxiliary.
        let app = NSApp();
        app.setActivationPolicy_(
            NSApplicationActivationPolicy::NSApplicationActivationPolicyAccessory,
        );
    }

    let Ok(ns_window_ptr) = window.ns_window() else { return };
    let ns_window = ns_window_ptr as id;

    unsafe {
        // Swap the underlying class from NSWindow to NSPanel. Panels float
        // above fullscreen windows reliably; plain NSWindows do not.
        if let Some(panel_class) = Class::get("NSPanel") {
            let _: *mut Class =
                objc::runtime::object_setClass(ns_window as *mut Object, panel_class);

            // NSWindowStyleMaskNonactivatingPanel = 1 << 7.
            // Combined with the existing borderless mask, this keeps the
            // webview from stealing focus on every redraw.
            let current_mask: u64 = msg_send![ns_window, styleMask];
            let new_mask = current_mask | (1u64 << 7);
            let _: () = msg_send![ns_window, setStyleMask: new_mask];
        }

        let _: () = msg_send![ns_window, setLevel: LEVEL];
        let _: () = msg_send![ns_window, setCollectionBehavior: BEHAVIOR];
        let _: () = msg_send![ns_window, setHasShadow: false];
        let _: () = msg_send![ns_window, setMovable: false];
        let _: () = msg_send![ns_window, setIgnoresMouseEvents: true];
        let _: () = msg_send![ns_window, setAnimationBehavior: 2i64]; // None

        let main_screen: id = NSScreen::mainScreen(nil);
        if main_screen == nil {
            return;
        }
        let screen_frame: NSRect = NSScreen::frame(main_screen);
        let win_frame: NSRect = NSWindow::frame(ns_window);

        let new_x = screen_frame.origin.x
            + (screen_frame.size.width - win_frame.size.width) / 2.0;
        let new_y = screen_frame.origin.y + screen_frame.size.height
            - win_frame.size.height;
        let _: () = msg_send![ns_window, setFrameOrigin: NSPoint::new(new_x, new_y)];

        eprintln!(
            "[vibe-notch] screen {:?} window {:?} -> origin ({}, {})",
            (screen_frame.size.width, screen_frame.size.height),
            (win_frame.size.width, win_frame.size.height),
            new_x,
            new_y
        );
    }
}
