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
  private let layerView: HdrLayerView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    layerView = HdrLayerView(frame: frame)
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

  func view() -> UIView { layerView }
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
