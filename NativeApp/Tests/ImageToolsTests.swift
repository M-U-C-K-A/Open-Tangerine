import AppKit
import CoreText
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import PDFKit

@main struct ImageToolsTests {
    static var failures = 0
    static func check(_ condition: Bool, _ name: String) {
        print("\(condition ? "PASS" : "FAIL") \(name)")
        if !condition { failures += 1 }
    }
    static func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let c = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    static func main() async throws {
        let ctx = CGContext(data: nil, width: 96, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<64 { for x in 0..<96 {
            ctx.setFillColor(CGColor(red: CGFloat(x % 23) / 23, green: CGFloat(y % 17) / 17, blue: CGFloat((x+y)%13)/13, alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }}
        let original = ctx.makeImage()!, input = CIImage(cgImage: ctx.makeImage()!)
        if let renderedInput = ImageOps.render(input) {
        let baseline = pixels(renderedInput)
        check(pixels(ImageOps.render(ImageOps.adjusted(input, .neutral))!) == baseline, "neutral adjustment preserves pixels")
        let adjustments: [(String, (inout PhotoAdjustments) -> Void)] = [
            ("exposure", {$0.exposure=1}), ("brightness", {$0.brightness=0.2}), ("contrast", {$0.contrast=1.5}),
            ("highlights", {$0.highlights=0.3}), ("shadows", {$0.shadows=0.8}), ("saturation", {$0.saturation=0}),
            ("vibrance", {$0.vibrance=1}), ("temperature", {$0.temperature=3000}), ("tint", {$0.tint=70}),
            ("sharpness", {$0.sharpness=1}), ("clarity", {$0.clarity=1}), ("dehaze", {$0.dehaze=1}),
            ("noise reduction", {$0.noiseReduction=1}), ("grain", {$0.grain=1}), ("vignette", {$0.vignette=1}),
            ("sepia", {$0.sepia=1}), ("monochrome", {$0.monochrome=true})]
        for (name, change) in adjustments {
            var a = PhotoAdjustments(); change(&a)
            if let result = ImageOps.render(ImageOps.adjusted(input,a)) {
                check(result.width == 96 && result.height == 64 && pixels(result) != baseline, "\(name) changes pixels and preserves dimensions")
            } else { check(false, "\(name) renders") }
        }
        for style in RedactionStyle.allCases {
            let result = ImageOps.render(ImageOps.redact(input,redactions:[Redaction(rect:CGRect(x:20,y:20,width:30,height:30),style:style)]))!
            check(pixels(result) != baseline && result.width == 96 && result.height == 64,"\(style) redaction changes pixels")
        }
        } else {
            print("BLOCKED CoreImage rendering unavailable in this process; adjustments and redaction require a graphics-capable run")
        }
        let baseline = pixels(original)
        for turns in 0..<4 {
            let rotated = try ImageOps.rotated(original, quarterTurns: turns, flipHorizontal: false, flipVertical: false)
            check(rotated.width == (turns%2 == 0 ? 96 : 64) && rotated.height == (turns%2 == 0 ? 64 : 96), "rotation \(turns) dimensions")
            let restored = try ImageOps.rotated(rotated, quarterTurns: -turns, flipHorizontal: false, flipVertical: false)
            check(pixels(restored) == baseline, "rotation \(turns) reverses exactly")
        }
        for horizontal in [true,false] {
            let flipped = try ImageOps.rotated(original, quarterTurns: 0, flipHorizontal: horizontal, flipVertical: !horizontal)
            check(try pixels(flipped) != baseline && pixels(ImageOps.rotated(flipped, quarterTurns: 0, flipHorizontal: horizontal, flipVertical: !horizontal)) == baseline, "flip \(horizontal) reverses exactly")
        }
        let resized = ImageIOBridge.scaled(original, to: CGSize(width: 24,height:16))
        check(resized.width == 24 && resized.height == 16, "resize dimensions")
        let crop = ImageIOBridge.cropped(original,to:CGRect(x:10,y:10,width:20,height:15))
        check(crop.width == 20 && crop.height == 15, "crop dimensions")
        var frame = ImageOps.FrameOptions(); frame.aspect = CGSize(width:16,height:9); frame.padding=0.1; frame.shadow=0
        let framed = ImageOps.framed(original,options:frame)!
        check(abs(Double(framed.width)/Double(framed.height)-16.0/9.0) < 0.025,"frame preserves selected 16:9 ratio with padding")
        for layout in ImageOps.CollageLayout.allCases {
            var options = ImageOps.CollageOptions(); options.width=240; options.height=180; options.spacing=8; options.layout=layout
            let frames = ImageOps.collageFrames(count:3,options:options)
            check(frames.count == 3 && frames.allSatisfy {$0.width>0 && $0.height>0 && CGRect(x:0,y:0,width:240,height:180).contains($0)},"\(layout) collage frames fit")
            let collage = ImageOps.collage([original,original,original],options:options)!
            check(collage.width==240 && collage.height==180,"\(layout) collage dimensions")
        }
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("image-tools-\(UUID())")
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let source=dir.appendingPathComponent("fixture.tiff")
        let dest=CGImageDestinationCreateWithURL(source as CFURL,UTType.tiff.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(dest,original,[kCGImagePropertyTIFFDictionary:[kCGImagePropertyTIFFArtist:"Private Artist"],kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:23.0,kCGImagePropertyGPSLatitudeRef:"N",kCGImagePropertyGPSLongitude:72.0,kCGImagePropertyGPSLongitudeRef:"E"]] as CFDictionary)
        check(CGImageDestinationFinalize(dest),"metadata fixture writes")
        let fields=await MetadataOps.read(source)
        check(fields.contains {$0.key=="Artist"},"metadata reads artist")
        let cleaned=dir.appendingPathComponent("clean.tiff")
        try await MetadataOps.write(source,edits:fields.filter(\.editable),removeAll:false,removeSensitive:true,to:cleaned,progress:{_ in})
        let cleanFields=await MetadataOps.read(cleaned)
        check(!cleanFields.contains {$0.key=="Artist" || $0.group=="GPS"},"remove sensitive does not restore artist from unchanged fields")
        let cleared=dir.appendingPathComponent("cleared.tiff")
        var clearEdits=fields.filter(\.editable)
        for index in clearEdits.indices where clearEdits[index].key == "Artist" { clearEdits[index].value = "" }
        try await MetadataOps.write(source,edits:clearEdits,removeAll:false,removeSensitive:false,to:cleared,progress:{_ in})
        check(!(await MetadataOps.read(cleared)).contains {$0.key=="Artist"}, "clearing editable metadata actually deletes value")
        let all=dir.appendingPathComponent("all.tiff")
        try await MetadataOps.write(source,edits:fields,removeAll:true,removeSensitive:false,to:all,progress:{_ in})
        check(!(await MetadataOps.read(all)).contains {$0.key=="Artist" || $0.group=="GPS"},"remove all metadata strips artist GPS")
        let text=dir.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to:text)
        check(try FileAction.hashReport([text]) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  abc.txt", "SHA256 known vector")
        let first=try FileAction.duplicateFiles([text])[0], second=try FileAction.duplicateFiles([text])[0]
        check(try first != second && Data(contentsOf:first) == Data("abc".utf8) && Data(contentsOf:second) == Data("abc".utf8), "duplicate keeps bytes and avoids overwriting")
        let pdf=PDFDocument(); pdf.insert(PDFPage(image:NSImage(cgImage:original,size:NSSize(width:96,height:64)))!,at:0)
        pdf.documentAttributes=[PDFDocumentAttribute.authorAttribute:"Private Person",PDFDocumentAttribute.titleAttribute:"Keep title"]
        let pdfURL=dir.appendingPathComponent("meta.pdf"); check(pdf.write(to:pdfURL), "PDF metadata fixture writes")
        let pdfClean=dir.appendingPathComponent("meta-clean.pdf")
        try await MetadataOps.write(pdfURL,edits:await MetadataOps.read(pdfURL),removeAll:false,removeSensitive:true,to:pdfClean,progress:{_ in})
        let pdfFields=await MetadataOps.read(pdfClean)
        check(!pdfFields.contains {$0.key=="Author"} && pdfFields.contains {$0.value=="Keep title"}, "PDF sensitive stripping retains title")
        // Background removal: an orange disc on a flat backdrop.
        let scene = CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        scene.setFillColor(CGColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1)); scene.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        let backdrop = scene.makeImage()!
        scene.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.05, alpha: 1)); scene.fillEllipse(in: CGRect(x: 110, y: 70, width: 100, height: 100))
        let subject = scene.makeImage()!
        do {
            let png = dir.appendingPathComponent("subject (no background).png")
            try ImageIOBridge.write(try BackgroundRemoval.remove(subject), to: png, format: .png)
            let cutout = try ImageIOBridge.load(png), rgba = pixels(cutout)
            func alpha(_ x: Int, _ y: Int) -> UInt8 { rgba[(y * cutout.width + x) * 4 + 3] }
            check(cutout.width == 320 && cutout.height == 240, "background removal keeps dimensions")
            check(![CGImageAlphaInfo.none, .noneSkipLast, .noneSkipFirst].contains(cutout.alphaInfo), "background removal writes a PNG with alpha")
            check([(2, 2), (317, 2), (2, 237), (317, 237), (40, 120), (280, 120), (160, 10), (160, 230)].allSatisfy { alpha($0.0, $0.1) == 0 }, "background removal clears the background")
            let center = (120 * 320 + 160) * 4
            check(alpha(160, 120) > 250 && rgba[center] > 200 && rgba[center + 1] < 110 && rgba[center + 2] < 40, "background removal keeps the subject and its color")
            let tight = try BackgroundRemoval.remove(subject, options: BackgroundRemoval.Options(cropToSubject: true))
            check(abs(tight.width - 100) <= 12 && abs(tight.height - 100) <= 12, "crop to subject trims to the subject (\(tight.width) × \(tight.height))")
            let soft = try BackgroundRemoval.remove(subject, options: BackgroundRemoval.Options(softness: 1)), softPixels = pixels(soft)
            check(softPixels != pixels(try BackgroundRemoval.remove(subject)) && softPixels[center + 3] > 250 && softPixels[3] == 0, "edge softness feathers only the edge")
        } catch OpenTangerineError.toolFailed(_, let reason) {
            print("BLOCKED Vision foreground masks unavailable in this process: \(reason)")
        }
        do {
            _ = try BackgroundRemoval.remove(backdrop)
            check(false, "background removal reports an image without a subject")
        } catch OpenTangerineError.invalidInput {
            check(true, "background removal reports an image without a subject")
        } catch OpenTangerineError.toolFailed(_, let reason) {
            print("BLOCKED Vision foreground masks unavailable in this process: \(reason)")
        }
        // Refining by hand: masks round-trip, rows line up with pixels, the wand and the brush.
        let pattern = (0..<(7 * 5)).map { UInt8(($0 * 37) % 256) }
        let roundTrip = BackgroundRemoval.MaskBuffer(BackgroundRemoval.MaskBuffer(width: 7, height: 5, values: pattern).ciImage(), width: 7, height: 5)
        check(roundTrip?.values == pattern, "refine mask survives a Core Image round trip unchanged")
        let topHalf = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        topHalf.setFillColor(gray: 1, alpha: 1); topHalf.fill(CGRect(x: 0, y: 4, width: 8, height: 4))
        let maskTop = BackgroundRemoval.MaskBuffer(CIImage(cgImage: topHalf.makeImage()!, options: [.colorSpace: NSNull()]), width: 8, height: 8)
        let redTop = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        redTop.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); redTop.fill(CGRect(x: 0, y: 4, width: 8, height: 4))
        let pixelsTop = BackgroundRemoval.Pixels(redTop.makeImage()!)
        check(maskTop?.values.first == 255 && maskTop?.values.last == 0 && pixelsTop?.rgba.first == 255 && pixelsTop?.rgba[(8 * 8 - 1) * 4] == 0, "refine mask and pixels both put the top row first")

        if let scenePixels = BackgroundRemoval.Pixels(subject) {
            func value(_ m: BackgroundRemoval.MaskBuffer, _ x: Int, _ y: Int) -> UInt8 { m.values[y * m.width + x] }
            var all = BackgroundRemoval.MaskBuffer(width: 320, height: 240, values: [UInt8](repeating: 255, count: 320 * 240))
            BackgroundRemoval.apply(.wand(point: CGPoint(x: 0.02, y: 0.02), tolerance: 0.1, keep: false), to: &all, pixels: scenePixels)
            check(value(all, 2, 2) == 0 && value(all, 317, 237) == 0 && value(all, 160, 120) == 255, "wand removes the connected backdrop and leaves the subject")
            var none = BackgroundRemoval.MaskBuffer(width: 320, height: 240, values: [UInt8](repeating: 0, count: 320 * 240))
            BackgroundRemoval.apply(.wand(point: CGPoint(x: 0.5, y: 0.5), tolerance: 0.1, keep: true), to: &none, pixels: scenePixels)
            check(value(none, 160, 120) == 255 && value(none, 120, 120) == 255 && value(none, 2, 2) == 0 && value(none, 100, 120) == 0, "wand brings back the clicked region only")
            var stroke = BackgroundRemoval.MaskBuffer(width: 320, height: 240, values: [UInt8](repeating: 0, count: 320 * 240))
            BackgroundRemoval.apply(.brush(path: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)], radius: 0.03, keep: true), to: &stroke, pixels: scenePixels)
            check((32...288).allSatisfy { value(stroke, $0, 120) == 255 } && value(stroke, 160, 140) == 0 && value(stroke, 10, 120) == 0, "brush paints a continuous stroke of the right width")
            // Edits are normalised: the same click lands on the same thing at twice the size.
            let big = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            big.interpolationQuality = .none
            big.draw(subject, in: CGRect(x: 0, y: 0, width: 640, height: 480))
            if let bigPixels = BackgroundRemoval.Pixels(big.makeImage()!) {
                var bigMask = BackgroundRemoval.MaskBuffer(width: 640, height: 480, values: [UInt8](repeating: 0, count: 640 * 480))
                BackgroundRemoval.refine(&bigMask, with: [.wand(point: CGPoint(x: 0.5, y: 0.5), tolerance: 0.1, keep: true)], pixels: bigPixels)
                check(value(bigMask, 320, 240) == 255 && value(bigMask, 240, 240) == 255 && value(bigMask, 4, 4) == 0, "refinements replay at full resolution")
            }
        }
        do {
            let restored = try BackgroundRemoval.remove(subject, refinements: [.wand(point: CGPoint(x: 0.02, y: 0.02), tolerance: 0.1, keep: true)])
            let restoredPixels = pixels(restored)
            check(restoredPixels[3] > 250 && restoredPixels[(120 * 320 + 160) * 4 + 3] > 250, "saving applies the refinements on top of Vision's mask")
        } catch OpenTangerineError.toolFailed(_, let reason) {
            print("BLOCKED Vision foreground masks unavailable in this process: \(reason)")
        }
        // Text recognition: reading order, a picture of text, a scanned PDF.
        let ordered = TextRecognition.lines(from: [
            .init(box: CGRect(x: 0.5, y: 0.78, width: 0.2, height: 0.05), text: "world"),
            .init(box: CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.05), text: "second"),
            .init(box: CGRect(x: 0.1, y: 0.79, width: 0.3, height: 0.05), text: "hello"),
        ])
        check(ordered == "hello world\nsecond", "text recognition keeps reading order")
        let words = CGContext(data: nil, width: 1200, height: 260, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        words.setFillColor(CGColor(gray: 1, alpha: 1)); words.fill(CGRect(x: 0, y: 0, width: 1200, height: 260))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Fresh tangerines 2026", attributes: [.font: NSFont.systemFont(ofSize: 96, weight: .bold), .foregroundColor: NSColor.black]))
        words.textPosition = CGPoint(x: 40, y: 90); CTLineDraw(line, words)
        let wordsImage = words.makeImage()!
        do {
            let read = try TextRecognition.text(in: wordsImage).lowercased()
            check(read.contains("tangerines") && read.contains("2026"), "text recognition reads a picture of text (\(read))")
            let png = dir.appendingPathComponent("words.png"), txt = dir.appendingPathComponent("words.txt")
            try ImageIOBridge.write(wordsImage, to: png, format: .png)
            try await Engines.convert(ConversionRequest(source: png, sourceFormat: .png, target: .txt, destination: txt, progress: { _ in }))
            check(try String(contentsOf: txt, encoding: .utf8).lowercased().contains("tangerines"), "PNG to TXT reads the text in the picture")
            let scan = PDFDocument(); scan.insert(PDFPage(image: NSImage(cgImage: wordsImage, size: NSSize(width: 600, height: 130)))!, at: 0)
            let scanURL = dir.appendingPathComponent("scan.pdf"), scanText = dir.appendingPathComponent("scan.txt")
            check(scan.write(to: scanURL), "scanned PDF fixture writes")
            try await Engines.convert(ConversionRequest(source: scanURL, sourceFormat: .pdf, target: .txt, destination: scanText, progress: { _ in }))
            check(try String(contentsOf: scanText, encoding: .utf8).lowercased().contains("tangerines"), "a scanned PDF becomes text")
            let copied = try TextRecognition.text(in: [png, scanURL]).lowercased()
            check(copied.components(separatedBy: "tangerines").count == 3, "Copy Text joins every file's text")
        } catch OpenTangerineError.toolFailed(_, let reason) {
            print("BLOCKED Vision text recognition unavailable in this process: \(reason)")
        }

        // Watermark: text in a corner, repeated, or a logo; the rest of the picture is untouched.
        let plain = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        plain.setFillColor(CGColor(gray: 0.4, alpha: 1)); plain.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        let grey = plain.makeImage()!, greyPixels = pixels(grey)
        func region(_ p: [UInt8], _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Bool {
            for y in y0..<y1 { for x in x0..<x1 where p[(y * 400 + x) * 4] != greyPixels[(y * 400 + x) * 4] { return true } }
            return false
        }
        let corner = pixels(try Watermark.apply(grey, options: Watermark.Options(text: "MARK", position: .bottomRight, size: 0.1, opacity: 1)))
        check(region(corner, 250, 230, 400, 300) && !region(corner, 0, 0, 200, 150), "watermark sits in the bottom-right corner only")
        let tiled = pixels(try Watermark.apply(grey, options: Watermark.Options(text: "MARK", position: .tiled, size: 0.06, opacity: 1)))
        check(region(tiled, 0, 0, 200, 150) && region(tiled, 200, 150, 400, 300), "a repeated watermark covers the whole picture")
        let stamp = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        stamp.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); stamp.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let logoed = pixels(try Watermark.apply(grey, options: Watermark.Options(position: .topLeft, size: 0.1, opacity: 1), logo: stamp.makeImage()!))
        check(logoed[(15 * 400 + 15) * 4] > 200 && logoed[(15 * 400 + 15) * 4 + 1] < 60 && !region(logoed, 200, 150, 400, 300), "a logo watermark lands top-left at full opacity")

        // ZIP: one item as name.zip, several as Archive.zip, never overwriting, contents intact.
        let zipDir = dir.appendingPathComponent("zip", isDirectory: true)
        try FileManager.default.createDirectory(at: zipDir.appendingPathComponent("Album"), withIntermediateDirectories: true)
        let note = zipDir.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: note)
        try Data("inside".utf8).write(to: zipDir.appendingPathComponent("Album/photo.txt"))
        let single = try await FileAction.zip([note]), again = try await FileAction.zip([note])
        check(single.lastPathComponent == "note.txt.zip" && again.lastPathComponent == "note.txt 2.zip", "zipping one item twice never overwrites")
        let archive = try await FileAction.zip([note, zipDir.appendingPathComponent("Album")])
        let unpacked = dir.appendingPathComponent("unzipped")
        _ = try await Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        check(archive.lastPathComponent == "Archive.zip"
              && (try? String(contentsOf: unpacked.appendingPathComponent("note.txt"), encoding: .utf8)) == "hello"
              && (try? String(contentsOf: unpacked.appendingPathComponent("Album/photo.txt"), encoding: .utf8)) == "inside", "several items, folders included, zip side by side")
        let batchNames = BackgroundRemoval.outputURLs(for: [dir.appendingPathComponent("a.jpg"), dir.appendingPathComponent("a.png")]) { $0.deletingLastPathComponent() }
        check(batchNames.map(\.lastPathComponent) == ["a (no background).png", "a (no background) 2.png"], "background removal batch outputs never collide")
        print("Image tool failures: \(failures)")
        if failures > 0 { exit(1) }
    }
}
