import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// QR code généré sur le téléphone (Core Image), agrandi sans lissage : chaque module reste
/// un carré net, quel que soit l'affichage. Fond blanc et marge pour que les appareils photo le lisent.
enum QRCode {
    private static let context = CIContext()

    static func image(for text: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct QRCodeView: View {
    let text: String
    var size: CGFloat = 220

    var body: some View {
        Group {
            if let img = QRCode.image(for: text) {
                Image(uiImage: img)
                    .interpolation(.none)          // pas de flou : les bords des modules restent nets
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .padding(14)                               // zone blanche autour (« quiet zone »)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .light)        // jamais inversé en mode sombre
        .accessibilityLabel("QR code")
    }
}
