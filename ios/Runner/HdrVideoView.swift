import AVFoundation
import Flutter
import UIKit

/// A platform view backed by an `AVSampleBufferDisplayLayer`.
///
/// Flutter composites its textures as SDR, so HDR video can only be shown as
/// HDR on a layer that the system composites itself. libmpv's `avfoundation`
/// video output (a local patch, see docs/ios-hdr.md) hands the decoder's
/// frames to this layer; Dart passes it the layer's address through `--wid`.
final class HdrVideoViewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "piliplus/hdr_video"

  private let messenger: FlutterBinaryMessenger

  private static let views = NSMapTable<NSNumber, HdrContainerView>.strongToWeakObjects()

  /// The layer of the platform view with this id, if it still exists.
  /// Picture-in-Picture uses it as its content source.
  static func layer(forView viewId: Int64) -> AVSampleBufferDisplayLayer? {
    views.object(forKey: NSNumber(value: viewId))?.layerView.displayLayer
  }

  /// Whether the view is on screen and its layer is showing frames.
  static func isShowingVideo(inView viewId: Int64) -> Bool {
    guard let view = views.object(forKey: NSNumber(value: viewId)) else { return false }
    return view.window != nil && !view.bounds.isEmpty
      && view.layerView.displayLayer.status == .rendering
  }

  /// While the layer is shown in the Picture-in-Picture window it is empty
  /// inline. Mirroring shows the same frames in place; it is turned on when
  /// the app comes back, so that the video is there before the window has
  /// returned, and off again once the layer shows the video itself.
  static func setMirroring(_ mirroring: Bool, forView viewId: Int64) {
    views.object(forKey: NSNumber(value: viewId))?.setMirroring(mirroring)
  }

  fileprivate static func register(_ view: HdrContainerView, viewId: Int64) {
    views.setObject(view, forKey: NSNumber(value: viewId))
  }

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    HdrVideoPlatformView(frame: frame, viewId: viewId, messenger: messenger)
  }
}

private final class HdrVideoPlatformView: NSObject, FlutterPlatformView {
  private let container: HdrContainerView
  private var layerView: HdrLayerView { container.layerView }
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    container = HdrContainerView(frame: frame)
    HdrVideoViewFactory.register(container, viewId: viewId)
    channel = FlutterMethodChannel(
      name: "\(HdrVideoViewFactory.viewType)_\(viewId)",
      binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "layer":
        // The video output retains the layer for as long as it uses it.
        let address = Unmanaged.passUnretained(self.layerView.displayLayer).toOpaque()
        result(NSNumber(value: Int64(Int(bitPattern: address))))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { container }
}

/// The video layer, and above it the mirror layer used during
/// Picture-in-Picture.
private final class HdrContainerView: UIView {
  /// The key libmpv's video output reads the second layer from.
  private static let mirrorKey = "mpvMirrorLayer"

  let layerView: HdrLayerView
  private var mirrorView: HdrLayerView?

  override init(frame: CGRect) {
    layerView = HdrLayerView(frame: CGRect(origin: .zero, size: frame.size))
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .black
    layerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(layerView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setMirroring(_ mirroring: Bool) {
    if mirroring {
      guard mirrorView == nil else { return }
      let mirror = HdrLayerView(frame: bounds)
      mirror.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      addSubview(mirror)
      mirrorView = mirror
      layerView.displayLayer.setValue(mirror.displayLayer, forKey: Self.mirrorKey)
    } else if let mirror = mirrorView {
      mirrorView = nil
      layerView.displayLayer.setValue(nil, forKey: Self.mirrorKey)
      mirror.removeFromSuperview()
    }
  }
}

private final class HdrLayerView: UIView {
  override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

  var displayLayer: AVSampleBufferDisplayLayer {
    layer as! AVSampleBufferDisplayLayer
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    // Flutter gives the view the video's aspect ratio and handles touches.
    displayLayer.videoGravity = .resize
    isUserInteractionEnabled = false
    backgroundColor = .black
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
