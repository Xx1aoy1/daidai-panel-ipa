import SwiftUI
import CoreImage.CIFilterBuiltins

/// 用 CoreImage 现场画二维码（不引第三方库）。
///
/// 面板的 `POST /security/2fa/setup` 只给 `otpauth://` 链接，二维码得客户端自己生成。
/// 认证器应用对二维码的容错不算宽容，所以这里用最近邻放大到接近像素级清晰，
/// 再交给 SwiftUI 按可用宽度缩放，避免系统插值把模块边界糊掉。
struct QRCodeImage: View {
    let text: String

    private static let context = CIContext()

    var body: some View {
        Group {
            if let image = Self.makeImage(from: text) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 28, weight: .light))
                    Text("二维码生成失败")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
                .frame(width: 180, height: 180)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private static func makeImage(from text: String) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // 纠错级别 M：认证器扫屏幕够用，码点也不会太密。
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
