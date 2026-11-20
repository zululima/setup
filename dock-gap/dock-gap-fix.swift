// Works around a macOS 27.2.1 bug: with the Dock set to hide automatically, WindowManager can keep
// the Dock's space reserved after the Dock has hidden, so maximized windows stop that far above the
// screen's edge. No single restart of the Dock or WindowManager has cleared it; three times it
// cleared on the third to fifth restart, once both had restarted. launchd starts both again. Every
// 20 s this reads the Dock's rectangle from the window server, and when auto-hide is on and the
// rectangle has kept a size for four readings in a row, it restarts the Dock, waits, and restarts
// WindowManager if the space is still held, logging each step. After three tries that leave it
// stuck it stops trying until the space clears. The LaunchAgent that install.sh writes runs it at
// login and keeps it running.
//
// Once the space clears, other apps' maximized windows grow back but Claude's stays short, so it
// grows each Claude window whose bottom edge sits where the reserved space began. That needs
// Accessibility permission, which it checks, asks for and logs at start, since a grant made while it
// runs did not reach it; install.sh says how a rebuild keeps it.
//
// Both reads are private functions. When one is missing after a macOS update it logs that and exits
// 0, which stops the agent until install.sh runs again.

import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

let stampFormat = DateFormatter()
stampFormat.dateFormat = "yyyy-MM-dd HH:mm:ss"
func log(_ message: String) {
  print("\(stampFormat.string(from: Date())) \(message)")
  fflush(stdout)
}

func symbol<T>(_ library: String, _ name: String, as type: T.Type) -> T? {
  guard let handle = dlopen(library, RTLD_NOW), let pointer = dlsym(handle, name) else { return nil }
  return unsafeBitCast(pointer, to: type)
}

typealias MainConnection = @convention(c) () -> Int32
typealias DockRect = @convention(c) (Int32, UnsafeMutablePointer<CGRect>, UnsafeMutablePointer<Int32>) -> Int32
typealias AutoHideEnabled = @convention(c) () -> Bool

let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
let appServices = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
guard let mainConnection = symbol(skyLight, "SLSMainConnectionID", as: MainConnection.self),
  let dockRect = symbol(skyLight, "SLSGetDockRectWithReason", as: DockRect.self),
  let autoHideEnabled = symbol(appServices, "CoreDockGetAutoHideEnabled", as: AutoHideEnabled.self)
else {
  log("a private function is missing after a macOS update, stopping")
  exit(0)
}

#if FORCE_STUCK
let interval: UInt32 = 1
let dockSettleSeconds: UInt32 = 2
#else
let interval: UInt32 = 20
let dockSettleSeconds: UInt32 = 45
#endif
let readingsBeforeRestart = 4
let restartsBeforeGivingUp = 3
let connection = mainConnection()

func restart(_ process: String) {
  let killall = Process()
  killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
  killall.arguments = [process]
  do {
    try killall.run()
    killall.waitUntilExit()
  } catch {
    log("killall \(process) failed: \(error)")
  }
}

func readDockRect() -> (error: Int32, rect: CGRect) {
  var rect = CGRect.zero
  var reason: Int32 = 0
  let error = dockRect(connection, &rect, &reason)
  return (error, rect)
}

func reservedDockSpace() -> CGRect? {
  let (error, rect) = readDockRect()
  guard error == 0, rect.width > 1, rect.height > 1 else { return nil }
  return rect
}

func frame(of window: AXUIElement) -> CGRect? {
  var positionRef: CFTypeRef?
  var sizeRef: CFTypeRef?
  var origin = CGPoint.zero
  var size = CGSize.zero
  guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
    let positionRef, let sizeRef,
    AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
  else { return nil }
  return CGRect(origin: origin, size: size)
}

func growShortClaudeWindows(reservedHeight: CGFloat) {
  guard AXIsProcessTrusted() else {
    log("no Accessibility permission, left Claude's window short")
    return
  }
  let screen = CGDisplayBounds(CGMainDisplayID())
  let shortBottom = screen.maxY - reservedHeight
  for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop") {
    var windowsRef: CFTypeRef?
    let element = AXUIElementCreateApplication(app.processIdentifier)
    guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windowsRef) == .success,
      let windows = windowsRef as? [AXUIElement]
    else { continue }
    for window in windows {
      guard let short = frame(of: window), abs(short.minX - screen.minX) < 1,
        abs(short.width - screen.width) < 1, abs(short.maxY - shortBottom) < 2
      else { continue }
      var full = CGSize(width: short.width, height: screen.maxY - short.minY)
      guard let value = AXValueCreate(.cgSize, &full) else { continue }
      let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
      log(result == .success
        ? "grew Claude's window from \(Int(short.height)) to \(Int(full.height)) points"
        : "could not grow Claude's window, AX error \(result.rawValue)")
    }
  }
}

var stuckReadings = 0
var restartsLeftStuck = 0
var heldReadings = 0
var heldHeight: CGFloat = 0
let first = readDockRect()
log("started, auto-hide \(autoHideEnabled() ? "on" : "off"), Dock rectangle "
  + "\(Int(first.rect.width))x\(Int(first.rect.height)), read error \(first.error)")
let promptOption = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
let trusted = AXIsProcessTrustedWithOptions([promptOption: true] as CFDictionary)
log(trusted
  ? "has Accessibility permission"
  : "asked for Accessibility permission, needed to grow Claude's window back")
#if RESIZE_ONCE
growShortClaudeWindows(reservedHeight: 90)
exit(0)
#endif
while true {
  sleep(interval)
  #if FORCE_STUCK
  let reserved: CGRect? = CGRect(x: 0, y: 0, width: 1, height: 1)
  #else
  let reserved = autoHideEnabled() ? reservedDockSpace() : nil
  #endif
  guard let reserved else {
    if restartsLeftStuck > 0 { log("Dock space cleared") }
    if heldReadings >= 2 { growShortClaudeWindows(reservedHeight: heldHeight) }
    stuckReadings = 0
    restartsLeftStuck = 0
    heldReadings = 0
    continue
  }
  heldReadings += 1
  heldHeight = reserved.height
  stuckReadings += 1
  guard stuckReadings >= readingsBeforeRestart else { continue }
  stuckReadings = 0
  guard restartsLeftStuck < restartsBeforeGivingUp else { continue }
  restartsLeftStuck += 1
  let size = "\(Int(reserved.width))x\(Int(reserved.height))"
  log("hidden Dock still reserves \(size) points, restarting the Dock")
  restart("Dock")
  sleep(dockSettleSeconds)
  if autoHideEnabled(), let still = reservedDockSpace() {
    log("still \(Int(still.width))x\(Int(still.height)) after the Dock restart, restarting WindowManager")
    restart("WindowManager")
  }
  if restartsLeftStuck == restartsBeforeGivingUp {
    log("\(restartsBeforeGivingUp) tries in a row, waiting until the space clears by itself")
  }
}
