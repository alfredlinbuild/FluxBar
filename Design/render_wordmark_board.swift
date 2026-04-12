import AppKit

let width = 1600
let height = 1080
let scriptURL = URL(fileURLWithPath: #filePath)
let outputURL = scriptURL
    .deletingLastPathComponent()
    .appendingPathComponent("fluxbar-wordmark-board.png")

struct Palette {
    static let ink = NSColor(calibratedRed: 0.12, green: 0.19, blue: 0.27, alpha: 1)
    static let muted = NSColor(calibratedRed: 0.44, green: 0.51, blue: 0.59, alpha: 1)
    static let bgTop = NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.99, alpha: 1)
    static let bgBottom = NSColor(calibratedRed: 0.87, green: 0.91, blue: 0.96, alpha: 1)
    static let card = NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.0, alpha: 0.92)
    static let border = NSColor(calibratedRed: 0.72, green: 0.79, blue: 0.86, alpha: 0.18)
    static let accentA0 = NSColor(calibratedRed: 0.34, green: 0.83, blue: 0.96, alpha: 1)
    static let accentA1 = NSColor(calibratedRed: 0.29, green: 0.47, blue: 1.00, alpha: 1)
    static let accentB0 = NSColor(calibratedRed: 0.49, green: 0.54, blue: 1.00, alpha: 1)
    static let accentB1 = NSColor(calibratedRed: 0.33, green: 0.39, blue: 0.92, alpha: 1)
    static let accentC0 = NSColor(calibratedRed: 0.33, green: 0.82, blue: 0.91, alpha: 1)
    static let accentC1 = NSColor(calibratedRed: 0.33, green: 0.40, blue: 0.96, alpha: 1)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawLinearGradient(in rect: CGRect, from start: NSColor, to end: NSColor, angle: CGFloat) {
    let gradient = NSGradient(starting: start, ending: end)
    gradient?.draw(in: rect, angle: angle)
}

func paragraph(alignment: NSTextAlignment = .left) -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    return style
}

func drawText(_ text: String, rect: CGRect, font: NSFont, color: NSColor, kern: Double = 0, alignment: NSTextAlignment = .left) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: kern,
        .paragraphStyle: paragraph(alignment: alignment)
    ]
    NSString(string: text).draw(in: rect, withAttributes: attrs)
}

func drawLine(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    path.lineWidth = width
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}

func drawAccentBar(in rect: CGRect, from start: NSColor, to end: NSColor) {
    roundedRect(rect, radius: rect.height / 2).addClip()
    drawLinearGradient(in: rect, from: start, to: end, angle: 0)
}

func drawCard(_ rect: CGRect) {
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = .init(width: 0, height: -10)
    shadow.shadowColor = NSColor(calibratedRed: 0.10, green: 0.17, blue: 0.24, alpha: 0.12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    Palette.card.setFill()
    roundedRect(rect, radius: 34).fill()
    NSGraphicsContext.restoreGraphicsState()
    Palette.border.setStroke()
    let border = roundedRect(rect.insetBy(dx: 0.5, dy: 0.5), radius: 34)
    border.lineWidth = 1
    border.stroke()
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = CGRect(x: 0, y: 0, width: width, height: height)
drawLinearGradient(in: canvas, from: Palette.bgTop, to: Palette.bgBottom, angle: -90)

NSColor.white.withAlphaComponent(0.70).setFill()
roundedRect(CGRect(x: 40, y: 860, width: 360, height: 180), radius: 180).fill()
NSColor.white.withAlphaComponent(0.45).setFill()
roundedRect(CGRect(x: 1220, y: 20, width: 260, height: 160), radius: 160).fill()

let top = CGFloat(height)

drawText("FluxBar Brand Study", rect: CGRect(x: 92, y: top - 112, width: 420, height: 24),
         font: .systemFont(ofSize: 15, weight: .bold), color: Palette.muted, kern: 1.8)
drawText("更有设计感的字标方向", rect: CGRect(x: 92, y: top - 182, width: 900, height: 64),
         font: .systemFont(ofSize: 56, weight: .bold), color: Palette.ink, kern: -1.0)
drawText("不再用“默认系统标题”的思路，而是把 FluxBar 当成一个桌面工具品牌字标来处理。下面 3 个方向重点看骨架、粗细对比、字距和整体气质。",
         rect: CGRect(x: 92, y: top - 240, width: 1100, height: 60),
         font: .systemFont(ofSize: 22, weight: .medium), color: Palette.muted, kern: 0)

let cards = [
    CGRect(x: 80, y: 540, width: 1440, height: 220),
    CGRect(x: 80, y: 280, width: 1440, height: 220),
    CGRect(x: 80, y: 20, width: 1440, height: 220)
]

for rect in cards { drawCard(rect) }

// Card A
drawText("A · Geometric Tech", rect: CGRect(x: 120, y: 708, width: 500, height: 28),
         font: .systemFont(ofSize: 24, weight: .bold), color: Palette.ink, kern: -0.3)
drawText("全小写，现代感最强。通过压缩字距、增强 bar 的重量，以及更几何的整体节奏，把它拉成一个更像独立软件品牌的字标。",
         rect: CGRect(x: 120, y: 660, width: 980, height: 48),
         font: .systemFont(ofSize: 19, weight: .medium), color: Palette.muted)
drawText("flux", rect: CGRect(x: 120, y: 574, width: 240, height: 84),
         font: .systemFont(ofSize: 90, weight: .bold), color: Palette.ink, kern: -7.2)
drawText("bar", rect: CGRect(x: 332, y: 574, width: 220, height: 84),
         font: .systemFont(ofSize: 90, weight: .black), color: Palette.ink, kern: -8.2)
drawAccentBar(in: CGRect(x: 130, y: 552, width: 318, height: 8), from: Palette.accentA0, to: Palette.accentA1)
drawText("lowercase / geometric / compressed / stronger finish",
         rect: CGRect(x: 120, y: 520, width: 700, height: 24),
         font: .systemFont(ofSize: 16, weight: .bold), color: Palette.muted)
Palette.accentA0.withAlphaComponent(0.14).setFill()
roundedRect(CGRect(x: 1420, y: 656, width: 64, height: 64), radius: 20).fill()
drawLine(from: CGPoint(x: 1442, y: 674), to: CGPoint(x: 1466, y: 698), color: Palette.accentA1, width: 5)
drawLine(from: CGPoint(x: 1466, y: 674), to: CGPoint(x: 1442, y: 698), color: Palette.accentA1, width: 5)

// Card B
drawText("B · Editorial Utility", rect: CGRect(x: 120, y: 448, width: 500, height: 28),
         font: .systemFont(ofSize: 24, weight: .bold), color: Palette.ink, kern: -0.3)
drawText("保留大小写，更像成熟桌面软件的品牌排版。重点是让 Flux 更轻、Bar 更重，用排版张力而不是颜色去建立识别度。",
         rect: CGRect(x: 120, y: 400, width: 980, height: 48),
         font: .systemFont(ofSize: 19, weight: .medium), color: Palette.muted)
drawText("Flux", rect: CGRect(x: 120, y: 314, width: 250, height: 84),
         font: .systemFont(ofSize: 88, weight: .medium), color: Palette.ink, kern: -6.8)
drawText("Bar", rect: CGRect(x: 342, y: 314, width: 220, height: 84),
         font: .systemFont(ofSize: 88, weight: .black), color: Palette.ink, kern: -8.0)
drawAccentBar(in: CGRect(x: 122, y: 292, width: 286, height: 3), from: Palette.accentB0, to: Palette.accentB1)
drawText("editorial / premium utility / contrast-driven",
         rect: CGRect(x: 120, y: 260, width: 700, height: 24),
         font: .systemFont(ofSize: 16, weight: .bold), color: Palette.muted)
Palette.accentB0.withAlphaComponent(0.14).setFill()
roundedRect(CGRect(x: 1416, y: 396, width: 68, height: 68), radius: 20).fill()
drawLine(from: CGPoint(x: 1450, y: 412), to: CGPoint(x: 1450, y: 444), color: Palette.accentB1, width: 5)
drawLine(from: CGPoint(x: 1434, y: 428), to: CGPoint(x: 1466, y: 428), color: Palette.accentB1, width: 5)

// Card C
drawText("C · Soft Futuristic", rect: CGRect(x: 120, y: 188, width: 500, height: 28),
         font: .systemFont(ofSize: 24, weight: .bold), color: Palette.ink, kern: -0.3)
drawText("圆润但不幼稚。适合希望保留一点亲和感，同时把品牌做得比默认系统字体更有未来感、更有记忆点的方向。",
         rect: CGRect(x: 120, y: 140, width: 980, height: 48),
         font: .systemFont(ofSize: 19, weight: .medium), color: Palette.muted)
drawText("flux", rect: CGRect(x: 120, y: 58, width: 240, height: 84),
         font: .systemFont(ofSize: 86, weight: .heavy), color: Palette.ink, kern: -6.8)
drawText("bar", rect: CGRect(x: 334, y: 58, width: 220, height: 84),
         font: .systemFont(ofSize: 86, weight: .bold), color: Palette.ink, kern: -6.8)
drawAccentBar(in: CGRect(x: 126, y: 36, width: 294, height: 8), from: Palette.accentC0, to: Palette.accentC1)
drawText("rounded geometry / friendlier / modern desktop brand",
         rect: CGRect(x: 120, y: 6, width: 760, height: 24),
         font: .systemFont(ofSize: 16, weight: .bold), color: Palette.muted)
Palette.accentC0.withAlphaComponent(0.13).setFill()
roundedRect(CGRect(x: 1418, y: 132, width: 64, height: 64), radius: 32).fill()
drawLine(from: CGPoint(x: 1450, y: 148), to: CGPoint(x: 1450, y: 180), color: Palette.accentC1, width: 5)
drawLine(from: CGPoint(x: 1434, y: 164), to: CGPoint(x: 1466, y: 164), color: Palette.accentC1, width: 5)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to create PNG data")
}

try data.write(to: outputURL)
print(outputURL.path)
