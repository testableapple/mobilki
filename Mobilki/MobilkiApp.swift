//
//  MobilkiApp.swift
//  Mobilki
//
//  Created by Alexey Alter-Pesotskiy on 6/27/25.
//

import SwiftUI
import AppKit

@main
struct MobilkiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.delegate = self
        popover.behavior = .transient

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "iphone.sizes", accessibilityDescription: nil)
            button.action = #selector(togglePopover(_:))
        }

        // Add key monitor for ESC key
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                if let popover = self?.popover, popover.isShown {
                    popover.performClose(nil)
                    return nil // Consume the event
                }
            }
            return event
        }
    }

    deinit {
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

                // Make the popover window focused so it can receive key events
                if let popoverWindow = popover.contentViewController?.view.window {
                    popoverWindow.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        return true
    }

    func popoverDidShow(_ notification: Notification) {
        // Ensure the popover window is focused when it shows
        if let popoverWindow = popover.contentViewController?.view.window {
            popoverWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
