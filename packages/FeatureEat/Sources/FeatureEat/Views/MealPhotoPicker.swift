import SwiftUI
import UIKit

/// The camera, or the photo library where there is no camera.
///
/// `UIImagePickerController` rather than `PhotosPicker` because this flow wants the
/// camera first and falls back to the library — in the simulator, and on a phone whose
/// camera the user has refused, `isSourceTypeAvailable(.camera)` is false and the same
/// sheet opens on the library instead. One wrapper, both cases, no branch at the call
/// site and nothing to explain on screen.
struct MealPhotoPicker: UIViewControllerRepresentable {
    /// JPEG bytes, already downscaled. `nil` when the user backed out.
    let picked: (Data?) -> Void

    static var hasCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Long enough edge for a plate to be readable, small enough that the upload is a
    /// second rather than a minute on a phone network.
    static let maxEdge: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.8

    func makeCoordinator() -> Coordinator {
        Coordinator(picked: picked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = Self.hasCamera ? .camera : .photoLibrary
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {
        context.coordinator.picked = picked
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {
        var picked: (Data?) -> Void

        init(picked: @escaping (Data?) -> Void) {
            self.picked = picked
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            picked(image.flatMap(Self.jpeg))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picked(nil)
        }

        /// Downscaled before it leaves the device: a 12-megapixel plate costs the user
        /// money and tells the model nothing a 1024-pixel one does not.
        static func jpeg(_ image: UIImage) -> Data? {
            let longest = max(image.size.width, image.size.height)
            guard longest > MealPhotoPicker.maxEdge else {
                return image.jpegData(compressionQuality: MealPhotoPicker.jpegQuality)
            }
            let scale = MealPhotoPicker.maxEdge / longest
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let scaled = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            return scaled.jpegData(compressionQuality: MealPhotoPicker.jpegQuality)
        }
    }
}
