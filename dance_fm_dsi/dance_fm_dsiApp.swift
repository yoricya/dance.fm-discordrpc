//
//  dance_fm_dsiApp.swift
//  dance_fm_dsi
//
//  Created by Ярослав on 07.06.2025.
//

import SwiftUI

@main
struct dance_fm_dsiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("setup popover..")
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 200, height: 150)
        popover.behavior = .transient
        
        
        print("init app..")

        if let app = new_app() {
            popover.contentViewController = NSHostingController(rootView: PopoverView(track_state: app.observe_state, track_app: app))
        } else {
            print("new_app() returned nilable state. Error occurred. App closed.")
            exit(1)
        }
        
        
        print("setup menu item button..")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        } else {
            print("cannot setup menu item button. App closed.")
            exit(1)
        }
    }
    
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

struct PopoverView: View {
    @ObservedObject var track_state: ObservableStateData
    var track_app: TrackApp
    
    var body: some View {
        VStack() {
            Text(track_state.title).bold().frame(maxWidth: .infinity, alignment: .leading)
            HStack() {
                Button(track_state.is_playing ? "Pause" : "Play"){
                    track_app.play_pause()
                }
                Button("Reset Stream"){
                    track_app.reset_state()
                }
                Button("RPC Reconnect"){
                    track_app.rpc?.reconnect()
                }
                Spacer()
                Text("RPC State: "+track_app.observe_state.rpc_status)
            }
            
            if track_state.live_latency > 1 {
                HStack() {
                    Text("Not live. Click \"Reset Stream\" to go live")
                    Spacer()
                }
                Spacer()
            }
            
        }.padding(10)
        .frame(width: 460)
    }
}

