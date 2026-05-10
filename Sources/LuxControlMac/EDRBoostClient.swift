import AppKit
import CoreGraphics
import Foundation
import Metal
import QuartzCore

protocol DisplayBoostClient: Sendable {
    func canBoost(for displayID: UInt32) async -> Bool
    func isBoostEnabled(for displayID: UInt32) async -> Bool
    func setBoostEnabled(_ enabled: Bool, for displayID: UInt32) async throws
}

final class EDRBoostClient: DisplayBoostClient, @unchecked Sendable {
    static let shared = EDRBoostClient()

    private let store = EDRBoostWindowStore()
    private let transferTableStore = DisplayTransferTableStore()

    private init() {}

    func canBoost(for displayID: UInt32) async -> Bool {
        await MainActor.run {
            guard let screen = NSScreen.screen(forDirectDisplayID: displayID) else {
                return false
            }

            return screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1
        }
    }

    func isBoostEnabled(for displayID: UInt32) async -> Bool {
        await store.isEnabled(for: displayID)
    }

    func setBoostEnabled(_ enabled: Bool, for displayID: UInt32) async throws {
        if enabled {
            try await store.enable(for: displayID)
            try transferTableStore.enableBoost(for: displayID)
        } else {
            transferTableStore.disableBoost(for: displayID)
            await store.disable(for: displayID)
        }
    }
}

private final class DisplayTransferTableStore: @unchecked Sendable {
    private struct SavedTable {
        var red: [Float]
        var green: [Float]
        var blue: [Float]
        var sampleCount: UInt32
    }

    private let lock = NSLock()
    private var savedTables: [UInt32: SavedTable] = [:]

    func enableBoost(for displayID: UInt32) throws {
        lock.lock()
        let alreadySaved = savedTables[displayID] != nil
        lock.unlock()

        if !alreadySaved {
            let table = try readCurrentTable(for: displayID)
            lock.lock()
            savedTables[displayID] = table
            lock.unlock()
        }

        try applyBoostTable(for: displayID)
    }

    func disableBoost(for displayID: UInt32) {
        lock.lock()
        let saved = savedTables.removeValue(forKey: displayID)
        lock.unlock()

        guard let saved else {
            CGDisplayRestoreColorSyncSettings()
            return
        }

        CGSetDisplayTransferByTable(
            CGDirectDisplayID(displayID),
            saved.sampleCount,
            saved.red,
            saved.green,
            saved.blue
        )
    }

    private func readCurrentTable(for displayID: UInt32) throws -> SavedTable {
        let capacity: UInt32 = 1024
        var red = [Float](repeating: 0, count: Int(capacity))
        var green = [Float](repeating: 0, count: Int(capacity))
        var blue = [Float](repeating: 0, count: Int(capacity))
        var sampleCount: UInt32 = 0

        let status = CGGetDisplayTransferByTable(
            CGDirectDisplayID(displayID),
            capacity,
            &red,
            &green,
            &blue,
            &sampleCount
        )
        guard status == .success, sampleCount > 0 else {
            throw makeError("CGGetDisplayTransferByTable failed with status \(status.rawValue)")
        }

        red.removeSubrange(Int(sampleCount)..<red.count)
        green.removeSubrange(Int(sampleCount)..<green.count)
        blue.removeSubrange(Int(sampleCount)..<blue.count)
        return SavedTable(red: red, green: green, blue: blue, sampleCount: sampleCount)
    }

    private func applyBoostTable(for displayID: UInt32) throws {
        let sampleCount: UInt32 = 1024
        let boosted = (0..<Int(sampleCount)).map { index -> Float in
            let x = Float(index) / Float(sampleCount - 1)
            let gammaLift = powf(x, 0.72)
            let highlightBoost = min(1.95, x * 1.95)
            let mixed = max(gammaLift, highlightBoost)
            return x == 0 ? 0 : mixed
        }

        let status = CGSetDisplayTransferByTable(
            CGDirectDisplayID(displayID),
            sampleCount,
            boosted,
            boosted,
            boosted
        )
        guard status == .success else {
            throw makeError("CGSetDisplayTransferByTable failed with status \(status.rawValue)")
        }
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "LuxControl.DisplayTransferTableStore",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

@MainActor
private final class EDRBoostWindowStore {
    private var windows: [UInt32: [NSWindow]] = [:]

    func isEnabled(for displayID: UInt32) -> Bool {
        windows[displayID] != nil
    }

    func enable(for displayID: UInt32) throws {
        guard windows[displayID] == nil else {
            return
        }
        guard let screen = NSScreen.screen(forDirectDisplayID: displayID) else {
            throw makeError("No NSScreen for display \(displayID)")
        }
        guard screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 else {
            throw makeError("Display \(displayID) does not report EDR support")
        }

        let ringWidth: CGFloat = 1
        let frame = screen.frame
        let ringFrames = [
            NSRect(x: frame.minX, y: frame.maxY - ringWidth, width: frame.width, height: ringWidth),
            NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: ringWidth),
            NSRect(x: frame.minX, y: frame.minY, width: ringWidth, height: frame.height),
            NSRect(x: frame.maxX - ringWidth, y: frame.minY, width: ringWidth, height: frame.height),
        ]

        let ringWindows = ringFrames.map { frame in
            let window = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .ignoresCycle,
                .stationary,
            ]
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isOpaque = false
            window.alphaValue = 0.01
            window.level = .screenSaver
            window.contentView = EDRBoostView(frame: NSRect(origin: .zero, size: frame.size))
            window.orderFrontRegardless()
            return window
        }

        windows[displayID] = ringWindows
    }

    func disable(for displayID: UInt32) {
        guard let ringWindows = windows.removeValue(forKey: displayID) else {
            return
        }

        for window in ringWindows {
            window.orderOut(nil)
        }
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "LuxControl.EDRBoostClient",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

private final class EDRBoostView: NSView {
    private let renderer = EDRMetalRenderer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        renderer.metalLayer.frame = bounds
        renderer.metalLayer.drawableSize = convertToBacking(bounds).size
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            renderer.stop()
        }
    }

    private func setupLayer() {
        wantsLayer = true
        layer = renderer.metalLayer
        renderer.metalLayer.frame = bounds
        renderer.metalLayer.drawableSize = convertToBacking(bounds).size
        renderer.start()
    }
}

@MainActor
private final class EDRMetalRenderer {
    let metalLayer = CAMetalLayer()

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var timer: Timer?

    init() {
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()

        metalLayer.device = device
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.opacity = 1
        metalLayer.backgroundColor = .clear
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    func start() {
        guard timer == nil else {
            return
        }

        draw()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.draw()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func draw() {
        guard let commandQueue,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        // A tiny EDR surface is enough to make WindowServer allocate extended
        // headroom, while avoiding a visible full-screen white blend.
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 8,
            green: 8,
            blue: 8,
            alpha: 1
        )

        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        encoder?.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

private extension NSScreen {
    static func screen(forDirectDisplayID displayID: UInt32) -> NSScreen? {
        screens.first { screen in
            guard let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return false
            }

            return screenNumber.uint32Value == displayID
        }
    }
}
