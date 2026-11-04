import SwiftUI
import VisionKit

/// `DataScannerViewController`, wrapped (spec §F3).
///
/// Barcodes only, one at a time, no guidance overlay: the camera is the control and
/// there is nothing to explain. On a device that cannot scan — the simulator, a
/// refused camera, an unsupported model — it draws nothing at all and the typed
/// barcode field beneath it carries the whole flow.
struct BarcodeScanner: UIViewControllerRepresentable {
    let isPaused: Bool
    let found: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(found: found)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.found = found
        guard Self.isAvailable, !isPaused else {
            controller.stopScanning()
            return
        }
        try? controller.startScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var found: (String) -> Void
        /// One payload per presentation: the scanner keeps recognising the same label
        /// while it is in frame, and a second callback would open a second sheet.
        private var delivered: Set<String> = []

        init(found: @escaping (String) -> Void) {
            self.found = found
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case let .barcode(barcode) = item,
                      let payload = barcode.payloadStringValue,
                      delivered.insert(payload).inserted else { continue }
                found(payload)
            }
        }
    }
}
