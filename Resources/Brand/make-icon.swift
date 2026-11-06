import AppKit
import CoreGraphics

let S: CGFloat = 1024
let bodyInset: CGFloat = 100
let body = CGRect(x: bodyInset, y: bodyInset, width: S - bodyInset * 2, height: S - bodyInset * 2)
let radius = body.width * 0.2237

func brandMark(in rect: CGRect, color: CGColor, alpha: CGFloat = 1) {
    let ctx = NSGraphicsContext.current!.cgContext
    let s = rect.width
    let ringStroke = s * 0.092
    let ringRadius = s * 0.205
    let center = CGPoint(x: rect.midX, y: rect.midY + s * 0.012)

    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(ringStroke)
    ctx.setLineCap(.round)

    // 圆环（镜头）
    ctx.addEllipse(in: CGRect(x: center.x - ringRadius, y: center.y - ringRadius,
                              width: ringRadius * 2, height: ringRadius * 2))
    ctx.strokePath()

    // 尾巴：底边贴在外圆上，向下左延伸，形成对话气泡
    let outer = ringRadius + ringStroke / 2
    let a1 = CGFloat.pi * 209 / 180
    let a2 = CGFloat.pi * 241 / 180
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: center.x + outer * cos(a1), y: center.y + outer * sin(a1)))
    tail.addLine(to: CGPoint(x: center.x + outer * 1.55 * cos(CGFloat.pi * 225 / 180),
                             y: center.y + outer * 1.55 * sin(CGFloat.pi * 225 / 180)))
    tail.addLine(to: CGPoint(x: center.x + outer * cos(a2), y: center.y + outer * sin(a2)))
    tail.closeSubpath()
    ctx.addPath(tail)
    ctx.setFillColor(color)
    ctx.fillPath()

    // 两行字幕
    let barHeight = s * 0.045
    let barX = center.x - s * 0.098
    let line1 = CGRect(x: barX, y: center.y + s * 0.035, width: s * 0.196, height: barHeight)
    let line2 = CGRect(x: barX, y: center.y - s * 0.062, width: s * 0.132, height: barHeight)
    ctx.addPath(CGPath(roundedRect: line1, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: line2, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
    ctx.setAlpha(alpha * 0.76)
    ctx.fillPath()
    ctx.restoreGState()
}

func renderIcon(size: CGFloat, to path: String) {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    // 渐变主体
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let gradient = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.36, green: 0.39, blue: 0.91, alpha: 1),
        CGColor(red: 0.20, green: 0.22, blue: 0.65, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [])
    // 顶部柔光
    let glow = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.16),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 900), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 900), endRadius: 620, options: [])
    ctx.restoreGState()

    // 内描边
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.setLineWidth(4)
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.strokePath()

    // 白色标志
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    brandMark(in: CGRect(x: 202, y: 202, width: 620, height: 620), color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()

    guard let image = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

renderIcon(size: 1024, to: "/tmp/logo/icon-1024.png")

// 透明背景的品牌标志（侧边栏 / 引导页用）
func renderMark(to path: String) {
    let size: CGFloat = 1024
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    brandMark(in: CGRect(x: 0, y: 0, width: 1024, height: 1024),
              color: CGColor(red: 0.31, green: 0.34, blue: 0.84, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    guard let image = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
renderMark(to: "/tmp/logo/mark-1024.png")

// 小尺寸预览：把 16/32/64/128 的实际像素放大 3 倍排一排
func renderPreview(to path: String) {
    let sizes: [CGFloat] = [16, 32, 64, 128]
    let scale: CGFloat = 3
    let gap: CGFloat = 24
    let width = sizes.reduce(CGFloat(0)) { $0 + $1 * scale + gap } + gap
    let height = 128 * scale + gap * 2
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.interpolationQuality = .none
    var x = gap
    for size in sizes {
        let temp = NSImage(size: NSSize(width: size, height: size))
        temp.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(contentsOfFile: "/tmp/logo/icon-1024.png")?.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        temp.unlockFocus()
        if let cg = temp.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(cg, in: CGRect(x: x, y: gap, width: size * scale, height: size * scale))
        }
        x += size * scale + gap
    }
    if let image = ctx.makeImage() {
        try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: path))
    }
}
renderPreview(to: "/tmp/logo/preview-small.png")
print("ok")
