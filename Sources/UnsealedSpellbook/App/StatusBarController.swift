import AppKit
import Observation
import SwiftUI

enum StatusBarAction: Equatable {
  case togglePopover
  case openSettings

  init(eventType: NSEvent.EventType?) {
    self = eventType == .rightMouseUp ? .openSettings : .togglePopover
  }
}

@MainActor
final class StatusBarController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private let store = UsageStore()
  private let navigation = DashboardNavigation()

  override init() {
    super.init()

    configureStatusItem()
    configurePopover()
    observeMenuBarTotal()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(defaultsChanged),
      name: UserDefaults.didChangeNotification,
      object: UserDefaults.standard
    )

    Task { [store] in await store.runRefreshLoop() }
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    let image = NSImage(
      systemSymbolName: "wand.and.stars",
      accessibilityDescription: "Unsealed Spellbook"
    )
    image?.isTemplate = true
    button.image = image
    button.imagePosition = .imageLeading
    button.target = self
    button.action = #selector(statusItemClicked)
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    updateStatusItem()
  }

  private func configurePopover() {
    popover.behavior = .transient
    popover.animates = true
    popover.contentSize = SpellbookDesign.windowSize
    popover.contentViewController = NSHostingController(
      rootView: LanguageRoot {
        UsageMenuView(store: store, navigation: navigation)
      }
    )
  }

  @objc private func statusItemClicked() {
    switch StatusBarAction(eventType: NSApp.currentEvent?.type) {
    case .openSettings:
      navigation.selectedPage = .settings
      showPopover()
    case .togglePopover:
      popover.isShown ? popover.performClose(nil) : showPopover()
    }
  }

  private func showPopover() {
    guard let button = statusItem.button else { return }
    if !popover.isShown {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  private func observeMenuBarTotal() {
    withObservationTracking {
      _ = store.menuBarTokenTotal
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.updateStatusItem()
        self?.observeMenuBarTotal()
      }
    }
  }

  @objc private func defaultsChanged() {
    updateStatusItem()
  }

  private func updateStatusItem() {
    let showTotal = AppPreferences.showMenuBarTotal()
    statusItem.length = showTotal ? NSStatusItem.variableLength : NSStatusItem.squareLength
    guard showTotal else {
      statusItem.button?.title = ""
      return
    }

    statusItem.button?.title =
      store.menuBarTokenTotal?.compactTokenCount(
        language: AppPreferences.language()
      ) ?? "—"
  }
}
