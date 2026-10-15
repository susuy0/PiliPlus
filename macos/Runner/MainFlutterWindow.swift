import Cocoa
import FlutterMacOS
import ObjectiveC.runtime

class MainFlutterWindow: NSWindow {
  private func applyOpaqueWindowAppearance() {
    // 恢复系统默认的不透明窗口背景
    self.isOpaque = true
    self.backgroundColor = .windowBackgroundColor

    // 正常显示标题栏时禁用透明效果
    if self.titleVisibility == .visible {
      self.titlebarAppearsTransparent = false
      self.styleMask.remove(.fullSizeContentView)
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    // 先不显示窗口
    self.isReleasedWhenClosed = false
    self.contentViewController = flutterViewController
    self.setFrame(self.frame, display: true)

    applyOpaqueWindowAppearance()

    VideoFrameTracker.install(
      registrar: flutterViewController.registrar(forPlugin: "PiliVideoFrames"))
    RegisterGeneratedPlugins(registry: flutterViewController)

    // 监听首帧渲染完成再显示窗口
    NotificationCenter.default.addObserver(
      forName: NSNotification.Name("io.flutter.embedding.engine.firstFrame"),
      object: flutterViewController.engine, queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      // window_manager 配置完成后恢复不透明样式
      self.applyOpaqueWindowAppearance()
      self.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    // 不在这里调用 makeKeyAndOrderFront
    super.awakeFromNib()
  }
}

/// Count actual texture submissions, rather than treating playback time as a
/// displayed frame. Forward all engine calls without changing their ordering.
private enum VideoFrameTracker {
  private static let lock = NSLock()
  private static var counts = [Int64: Int64]()
  private static var installed = false
  private static var channel: FlutterMethodChannel?

  static func install(registrar: FlutterPluginRegistrar) {
    guard !installed, let cls = object_getClass(registrar.textures) else { return }
    guard ["registerTexture:", "textureFrameAvailable:", "unregisterTexture:"].allSatisfy({
      class_getInstanceMethod(cls, NSSelectorFromString($0)) != nil
    }) else { return }
    installed = true
    let channel = FlutterMethodChannel(
      name: "com.example.piliplus/video_frames", binaryMessenger: registrar.messenger)
    Self.channel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "frameSerial" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
        let id = args["textureId"] as? NSNumber else {
        result(nil)
        return
      }
      lock.lock()
      let serial = counts[id.int64Value]
      lock.unlock()
      result(serial)
    }
    let register = NSSelectorFromString("registerTexture:")
    hook(cls, register) { original in
      typealias Function = @convention(c) (AnyObject, Selector, AnyObject) -> Int64
      let function = unsafeBitCast(original, to: Function.self)
      let block: @convention(block) (AnyObject, AnyObject) -> Int64 = { object, texture in
        let id = function(object, register, texture)
        lock.lock()
        counts[id] = 0
        lock.unlock()
        return id
      }
      return unsafeBitCast(block, to: AnyObject.self)
    }
    let frame = NSSelectorFromString("textureFrameAvailable:")
    hook(cls, frame) { original in
      typealias Function = @convention(c) (AnyObject, Selector, Int64) -> Void
      let function = unsafeBitCast(original, to: Function.self)
      let block: @convention(block) (AnyObject, Int64) -> Void = { object, id in
        function(object, frame, id)
        lock.lock()
        if let serial = counts[id] { counts[id] = serial &+ 1 }
        lock.unlock()
      }
      return unsafeBitCast(block, to: AnyObject.self)
    }
    let unregister = NSSelectorFromString("unregisterTexture:")
    hook(cls, unregister) { original in
      typealias Function = @convention(c) (AnyObject, Selector, Int64) -> Void
      let function = unsafeBitCast(original, to: Function.self)
      let block: @convention(block) (AnyObject, Int64) -> Void = { object, id in
        lock.lock()
        counts.removeValue(forKey: id)
        lock.unlock()
        function(object, unregister, id)
      }
      return unsafeBitCast(block, to: AnyObject.self)
    }
  }

  private static func hook(_ cls: AnyClass, _ selector: Selector,
    _ makeBlock: (IMP) -> AnyObject) {
    guard let method = class_getInstanceMethod(cls, selector) else { return }
    let replacement = imp_implementationWithBlock(makeBlock(method_getImplementation(method)))
    if !class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)) {
      method_setImplementation(method, replacement)
    }
  }
}
