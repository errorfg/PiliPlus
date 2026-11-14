import Flutter
import UIKit

/// Reports the parts of the Flutter view that UIKit reserves for system
/// elements, such as the status bar and Dynamic Island at the top of iPhone
/// Duo's vertical bar strip.
///
/// They are the view's `reservedRegions(kind: .occlusion)`, added in the iOS
/// 27.1 SDK. Flutter does not pass them to Dart on iOS, so they are read here.
final class ReservedRegionsPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.example.piliplus/reserved_regions",
      binaryMessenger: registrar.messenger())
    let instance = ReservedRegionsPlugin(channel: channel, registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private let channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?
  private var observer: ReservedRegionsObserver?

  private init(channel: FlutterMethodChannel, registrar: FlutterPluginRegistrar) {
    self.channel = channel
    self.registrar = registrar
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "observe":
      result(observe())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Starts reporting the Flutter view's regions, and returns them.
  private func observe() -> [[Double]] {
    guard let view = registrar?.viewController?.view else { return [] }
    if let observer, observer.superview === view { return observer.regions }
    observer?.removeFromSuperview()
    let observer = ReservedRegionsObserver { [weak self] regions in
      self?.channel.invokeMethod("didChange", arguments: regions)
    }
    view.addSubview(observer)
    self.observer = observer
    return observer.regions
  }
}

/// A hidden view that reports its superview's occlusion regions, each as
/// `[left, top, right, bottom]` in points, whenever they change.
private final class ReservedRegionsObserver: UIView {
  private let onChange: ([[Double]]) -> Void
  private(set) var regions: [[Double]] = []
  private var timer: Timer?

  init(onChange: @escaping ([[Double]]) -> Void) {
    self.onChange = onChange
    super.init(frame: .zero)
    isHidden = true
    isUserInteractionEnabled = false
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    frame = superview?.bounds ?? .zero
    regions = read()
  }

  // UIKit sends nothing when the regions change, and a Dynamic Island that
  // appears or goes need not move any layout of this view. So besides on
  // layout, they are read a few times a second while the view is in a window.
  override func didMoveToWindow() {
    super.didMoveToWindow()
    timer?.invalidate()
    timer = nil
    guard window != nil else { return }
    refresh()
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      self?.refresh()
    }
    timer.tolerance = 0.1
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    refresh()
  }

  @objc private func refresh() {
    let regions = read()
    guard regions != self.regions else { return }
    self.regions = regions
    onChange(regions)
  }

  private func read() -> [[Double]] {
    // The iOS 27.1 SDK's UIKit is the first with reserved regions.
    #if canImport(UIKit, _version: 9127.0.85)
    if #available(iOS 27.1, *), let superview {
      return superview.reservedRegions(kind: .occlusion).map { region in
        let frame = region.frame
        return [frame.minX, frame.minY, frame.maxX, frame.maxY].map(Double.init)
      }
    }
    #endif
    return []
  }
}
