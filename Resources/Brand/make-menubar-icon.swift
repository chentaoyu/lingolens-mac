// 生成菜单栏 template 图标（矢量 PDF）与放大预览图。
// 用法：swift Resources/Brand/make-menubar-icon.swift
import AppKit

let size = CGSize(width: 18, height: 18) // 菜单栏标准 18pt
let out = "App/Assets.xcassets/MenuBarIcon.imageset/menubar-icon.pdf"

func drawMark(_ ctx: CGContext) {
    ctx.setFillColor(.black)
    ctx.setStrokeColor(.black)
    let c = CGPoint(x: 9.6, y: 9.6)
    let r: CGFloat = 5.7, stroke: CGFloat = 1.9
    let outer = r + stroke / 2

    // 圆环（镜头）
    ctx.setLineWidth(stroke)
    ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

    // 左下尾巴（对话气泡）
    func p(_ deg: CGFloat, _ k: CGFloat = 1) -> CGPoint {
        CGPoint(x: c.x + outer * k * cos(deg * .pi / 180), y: c.y + outer * k * sin(deg * .pi / 180))
    }
    ctx.move(to: p(205)); ctx.addLine(to: p(225, 1.42)); ctx.addLine(to: p(245)); ctx.closePath()
    ctx.fillPath()

    // 两行字幕
    let h: CGFloat = 1.6
    for (w, y) in [(5.4, c.y + 0.75), (3.4, c.y - 2.35)] as [(CGFloat, CGFloat)] {
        let rect = CGRect(x: c.x - 2.7, y: y, width: w, height: h)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        ctx.fillPath()
    }
}

// 矢量 PDF
var box = CGRect(origin: .zero, size: size)
let pdf = CGContext(URL(fileURLWithPath: out) as CFURL, mediaBox: &box, nil)!
pdf.beginPDFPage(nil); drawMark(pdf); pdf.endPDFPage(); pdf.closePDF()

// 预览：1x / 2x 实际像素，浅色与深色菜单栏各一行，再放大 6 倍
let scales: [CGFloat] = [1, 2]
let cell: CGFloat = 36, zoom: CGFloat = 6
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cell * 2 * zoom), pixelsHigh: Int(cell * 2 * zoom),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let pctx = NSGraphicsContext.current!.cgContext
pctx.interpolationQuality = .none
for (row, dark) in [false, true].enumerated() {
    for (col, s) in scales.enumerated() {
        let px = Int(size.width * s)
        let bmp = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bmp.setFillColor(dark ? CGColor(gray: 0.16, alpha: 1) : CGColor(gray: 0.93, alpha: 1))
        bmp.fill(CGRect(x: 0, y: 0, width: px, height: px))
        bmp.scaleBy(x: s, y: s)
        bmp.beginTransparencyLayer(auxiliaryInfo: nil)
        drawMark(bmp)
        if dark { bmp.setBlendMode(.sourceIn); bmp.setFillColor(.white); bmp.fill(box) }
        bmp.endTransparencyLayer()
        let origin = CGPoint(x: CGFloat(col) * cell * zoom, y: CGFloat(1 - row) * cell * zoom)
        pctx.draw(bmp.makeImage()!, in: CGRect(origin: origin, size: CGSize(width: cell * zoom, height: cell * zoom)))
    }
}
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Resources/Brand/menubar-preview.png"))
print("✅ \(out)")
