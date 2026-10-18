import AppKit

/// Original vector mark, shared by app artwork and the template menu-bar icon.
enum BrandArtwork {
    static func image(size: CGFloat, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width
            if !template {
                NSColor(srgbRed: 1, green: 0.36, blue: 0.06, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.04, dy: s * 0.04), xRadius: s * 0.22, yRadius: s * 0.22).fill()
            }
            (template ? NSColor.labelColor : NSColor.white).setStroke()
            let fruit = NSBezierPath(ovalIn: NSRect(x: s * 0.23, y: s * 0.2, width: s * 0.54, height: s * 0.52))
            fruit.lineWidth = s * 0.055
            fruit.stroke()
            let leaf = NSBezierPath()
            leaf.move(to: NSPoint(x: s * 0.49, y: s * 0.73))
            leaf.curve(to: NSPoint(x: s * 0.72, y: s * 0.84), controlPoint1: NSPoint(x: s * 0.49, y: s * 0.88), controlPoint2: NSPoint(x: s * 0.66, y: s * 0.88))
            leaf.curve(to: NSPoint(x: s * 0.49, y: s * 0.73), controlPoint1: NSPoint(x: s * 0.70, y: s * 0.73), controlPoint2: NSPoint(x: s * 0.59, y: s * 0.71))
            (template ? NSColor.labelColor : NSColor.white).setFill()
            leaf.fill()
            let shine = NSBezierPath()
            shine.move(to: NSPoint(x: s * 0.34, y: s * 0.49))
            shine.curve(to: NSPoint(x: s * 0.43, y: s * 0.61), controlPoint1: NSPoint(x: s * 0.34, y: s * 0.56), controlPoint2: NSPoint(x: s * 0.39, y: s * 0.61))
            shine.lineWidth = s * 0.04
            shine.lineCapStyle = .round
            shine.stroke()
            return true
        }
        image.isTemplate = template
        return image
    }
}
