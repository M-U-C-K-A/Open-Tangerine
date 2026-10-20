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
        try await MetadataOps.write(source,tags:[:],removeAll:false,removeSensitive:true,to:cleaned,progress:{_ in})
        let cleanFields=await MetadataOps.read(cleaned)
        check(!cleanFields.contains {$0.key=="Artist" || $0.group=="GPS"},"remove sensitive does not restore artist from unchanged fields")
        let cleared=dir.appendingPathComponent("cleared.tiff")
        try await MetadataOps.write(source,tags:[.artist:""],removeAll:false,removeSensitive:false,to:cleared,progress:{_ in})
        check(!(await MetadataOps.read(cleared)).contains {$0.key=="Artist"}, "clearing editable metadata actually deletes value")
        let all=dir.appendingPathComponent("all.tiff")
        try await MetadataOps.write(source,tags:[.title:"ignored"],removeAll:true,removeSensitive:false,to:all,progress:{_ in})
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
        try await MetadataOps.write(pdfURL,tags:[:],removeAll:false,removeSensitive:true,to:pdfClean,progress:{_ in})
        let pdfFields=await MetadataOps.read(pdfClean)
        check(!pdfFields.contains {$0.key=="Author"} && pdfFields.contains {$0.value=="Keep title"}, "PDF sensitive stripping retains title")
        let pdfTagged=dir.appendingPathComponent("meta-tagged.pdf")
        try await MetadataOps.write(pdfURL,tags:[.title:"New title",.keywords:"citrus, report"],removeAll:false,removeSensitive:false,to:pdfTagged,progress:{_ in})
        let pdfTags=await MetadataOps.readTags(pdfTagged)
        check(pdfTags[.title]=="New title" && pdfTags[.keywords]=="citrus, report" && pdfTags[.artist]=="Private Person", "PDF fields change one by one, the rest kept")
        // Fields a picture doesn't have yet are added; changing one keeps the others.
        for format in [FileFormat.jpg, .png, .heic, .tiff] {
            let plain=dir.appendingPathComponent("plain-meta.\(format.fileExtension)"), tagged=dir.appendingPathComponent("tagged.\(format.fileExtension)"), retagged=dir.appendingPathComponent("retagged.\(format.fileExtension)")
            try ImageIOBridge.write(original,to:plain,format:format)
            try await MetadataOps.write(plain,tags:[.title:"Orange sky",.artist:"Ada",.keywords:"citrus, sky",.copyright:"© 2026",.description:"A test"],removeAll:false,removeSensitive:false,to:tagged,progress:{_ in})
            let back=await MetadataOps.readTags(tagged)
            check(back[.title]=="Orange sky" && back[.artist]=="Ada" && back[.keywords]=="citrus, sky" && back[.copyright]=="© 2026" && back[.description]=="A test", "\(format.displayName): new fields are written and read back \(back)")
            try await MetadataOps.write(tagged,tags:[.title:"Lemon",.copyright:""],removeAll:false,removeSensitive:false,to:retagged,progress:{_ in})
            let again=await MetadataOps.readTags(retagged)
            check(again[.title]=="Lemon" && again[.artist]=="Ada" && again[.copyright]==nil && ImageIOBridge.pixelSize(retagged)==CGSize(width:original.width,height:original.height), "\(format.displayName): one field changed, one removed, the rest kept \(again)")
        }
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

        // Upscale: tiles cover the picture; Enlarge and Enhance double or quadruple it, transparency kept.
        check(Upscale.origins(length: 2000, tile: 960, overlap: 24) == [0, 936, 1040] && Upscale.origins(length: 500, tile: 500, overlap: 24) == [0], "upscale tiles cover every pixel, the last flush with the edge")
        let detailed = CGContext(data: nil, width: 1300, height: 1000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in stride(from: 0, to: 1000, by: 20) { for x in stride(from: 0, to: 1300, by: 20) {
            detailed.setFillColor(CGColor(red: CGFloat(x % 260) / 260, green: CGFloat(y % 200) / 200, blue: 0.5, alpha: 1))
            detailed.fill(CGRect(x: x, y: y, width: 20, height: 20))
        }}
        let detailedImage = detailed.makeImage()!
        let enlarged = try await Upscale.upscale(detailedImage, factor: 2, method: .enlarge)
        check(enlarged.width == 2600 && enlarged.height == 2000, "enlarge doubles the size")
        do {
            let enhanced = try await Upscale.upscale(detailedImage, factor: 2, method: .enhance)
            check(enhanced.width == 2600 && enhanced.height == 2000, "enhance doubles the size through tiles (\(enhanced.width) × \(enhanced.height))")
            let e = pixels(enhanced), source = pixels(detailedImage)
            // A block well inside a tile seam keeps its colour.
            let probe = { (img: [UInt8], w: Int, x: Int, y: Int) in Int(img[(y * w + x) * 4]) }
            check(abs(probe(e, 2600, 1890, 1010) - probe(source, 1300, 945, 505)) < 40, "enhance keeps colours across tile seams")
            let four = try await Upscale.upscale(stamp.makeImage()!, factor: 4, method: .enhance)
            check(four.width == 160 && four.height == 80, "enhance ×4 runs twice")
            let between = try await Upscale.resize(stamp.makeImage()!, to: CGSize(width: 100, height: 50), method: .enhance)
            check(between.width == 100 && between.height == 50, "enhance ×2.5 rebuilds detail, then settles on the size")
            let clear = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            clear.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1)); clear.fillEllipse(in: CGRect(x: 50, y: 50, width: 100, height: 100))
            let clearUp = pixels(try await Upscale.upscale(clear.makeImage()!, factor: 2, method: .enhance))
            check(clearUp[3] < 10 && clearUp[(200 * 400 + 200) * 4 + 3] > 245, "enhance keeps transparency")
        } catch OpenTangerineError.toolFailed(_, let reason) {
            print("BLOCKED super resolution unavailable in this process: \(reason)")
        }
        do {
            _ = try await Upscale.upscale(detailedImage, factor: 16, method: .enlarge)
            check(false, "an oversized upscale is refused")
        } catch OpenTangerineError.invalidInput {
            check(true, "an oversized upscale is refused")
        }

        // Resize & compress: one size rule for every picture; growing lands on the exact size.
        var sizing = ImageSizing(mode: .longEdge, longEdge: 1000)
        check(sizing.target(for: CGSize(width: 2000, height: 1000)) == CGSize(width: 1000, height: 500) && sizing.target(for: CGSize(width: 800, height: 600)) == CGSize(width: 800, height: 600), "the long edge shrinks, and never enlarges unasked")
        sizing.enlargeToLongEdge = true
        check(sizing.target(for: CGSize(width: 800, height: 600)) == CGSize(width: 1000, height: 750) && sizing.enlarges(CGSize(width: 800, height: 600)), "the long edge enlarges on request")
        check(ImageSizing(mode: .percent, percent: 200).target(for: CGSize(width: 300, height: 101)) == CGSize(width: 600, height: 202), "percent scales both sides")
        check(ImageSizing(mode: .exact, width: 500, height: 500).target(for: CGSize(width: 1000, height: 250)) == CGSize(width: 500, height: 125), "exact fits inside, proportions kept")
        check(ImageSizing(mode: .exact, width: 500, height: 500, keepAspect: false).target(for: CGSize(width: 1000, height: 250)) == CGSize(width: 500, height: 500), "exact can stretch")
        check(ImageResizer.suffix(sizing: ImageSizing(mode: .original), size: CGSize(width: 10, height: 10), compressing: true) == "compressed" && ImageResizer.suffix(sizing: ImageSizing(mode: .percent, percent: 200), size: CGSize(width: 10, height: 10), compressing: false) == "enlarged" && ImageResizer.suffix(sizing: ImageSizing(mode: .percent, percent: 50), size: CGSize(width: 10, height: 10), compressing: true) == "resized", "the copy's name says what was done")
        let uneven = try await Upscale.resize(detailedImage, to: CGSize(width: 1950, height: 1100), method: .enlarge)
        check(uneven.width == 1950 && uneven.height == 1100, "enlarge lands on an exact, uneven size")
        let shrunk = try await Upscale.resize(detailedImage, to: CGSize(width: 650, height: 500), method: .enhance)
        check(shrunk.width == 650 && shrunk.height == 500, "shrinking needs no enhancement")
        let sizingSource = dir.appendingPathComponent("sizing.jpg"), sizingOut = dir.appendingPathComponent("sizing small.jpg")
        try ImageIOBridge.write(detailedImage, to: sizingSource, format: .jpg, quality: 0.95)
        try await ImageResizer.process(sizingSource, sizing: ImageSizing(mode: .percent, percent: 50), method: .enlarge, preset: .strong, targetBytes: nil, quality: 0.9, to: sizingOut, progress: { _ in })
        check(ImageIOBridge.pixelSize(sizingOut) == CGSize(width: 650, height: 500) && FileSizeFormatter.size(of: sizingOut) < FileSizeFormatter.size(of: sizingSource), "resize and compress in one pass: half the size, a lighter file")
        // Social formats: the network's exact size, cropped around the subject or fitted on blurred sides.
        let storyCrop = SocialFrame.framed(detailedImage, aspect: SocialFormat.instagramStory.size, fill: true, focus: CGPoint(x: 0.9, y: 0.5))
        let storyRatio = Double(storyCrop.width) / Double(storyCrop.height)
        check(abs(storyRatio - 0.5625) < 0.01 && storyCrop.height == 1000, "a story crop takes the full height at 9:16 (\(storyCrop.width) × \(storyCrop.height))")
        let fitted = SocialFrame.framed(detailedImage, aspect: SocialFormat.instagramStory.size, fill: false, focus: CGPoint(x: 0.5, y: 0.5))
        let fittedRatio = Double(fitted.width) / Double(fitted.height)
        check(fitted.width == 1300 && abs(fittedRatio - 0.5625) < 0.01, "fitting keeps the whole picture on a taller canvas (\(fitted.width) × \(fitted.height))")
        let postOut = dir.appendingPathComponent("photo instagram.jpg")
        try await ImageResizer.process(sizingSource, sizing: ImageSizing(mode: .social, social: .instagramPost), method: .enlarge, preset: nil, targetBytes: nil, quality: 0.9, to: postOut, progress: { _ in })
        check(ImageIOBridge.pixelSize(postOut) == CGSize(width: 1080, height: 1350) && ImageResizer.suffix(sizing: ImageSizing(mode: .social, social: .youtubeThumbnail), size: .zero, compressing: false) == "youtube", "an Instagram post comes out at 1080 × 1350")

        // An alpha channel that is opaque everywhere is no transparency: such PNGs become JPEGs,
        // and the size asked for is kept whatever the compression.
        let holey = CGContext(data: nil, width: 60, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        holey.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1)); holey.fillEllipse(in: CGRect(x: 0, y: 0, width: 60, height: 40))
        check(!ImageIOBridge.hasTransparency(detailedImage) && !ImageIOBridge.hasTransparency(stamp.makeImage()!) && ImageIOBridge.hasTransparency(holey.makeImage()!), "only see-through pixels count as transparency")
        let opaquePNG = dir.appendingPathComponent("opaque.png")
        try ImageIOBridge.write(detailedImage, to: opaquePNG, format: .png)
        check(ImageResizer.outputFormat(for: opaquePNG, compressing: true) == .jpg && ImageResizer.outputFormat(for: opaquePNG, compressing: false) == .png, "an opaque PNG is compressed as a JPEG")
        let strongOut = dir.appendingPathComponent("strong.jpg")
        try await ImageResizer.process(opaquePNG, sizing: ImageSizing(mode: .longEdge, longEdge: 800), method: .enlarge, preset: .strong, targetBytes: nil, quality: 0.9, to: strongOut, progress: { _ in })
        check(ImageIOBridge.pixelSize(strongOut) == CGSize(width: 800, height: 615), "Strong keeps the long edge asked for (\(ImageIOBridge.pixelSize(strongOut)))")

        // Color palette: two flat colors give two swatches with their shares; the eyedropper reads pixels.
        let halves = CGContext(data: nil, width: 300, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        halves.setFillColor(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)); halves.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        halves.setFillColor(CGColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 1)); halves.fill(CGRect(x: 200, y: 0, width: 100, height: 100))
        let grid = PixelGrid(halves.makeImage()!)!
        let swatches = grid.palette(count: 6)
        check(swatches.count == 2 && swatches[0].hex == "#FF8000" && swatches[1].hex == "#0066FF" && abs(swatches[0].share - 2.0 / 3) < 0.05, "the palette finds both colors, the biggest first: \(swatches.map(\.hex))")
        check(grid.color(atX: 0.1, y: 0.5)?.hex == "#FF8000" && grid.color(atX: 0.95, y: 0.5)?.hex == "#0066FF", "the eyedropper reads the pixel under it")
        let orange = PaletteColor(red: 1, green: 0.5, blue: 0)
        check(orange.text(.rgb) == "rgb(255, 128, 0)" && orange.text(.hsl) == "hsl(30, 100%, 50%)" && orange.text(.swiftUI) == "Color(red: 1.000, green: 0.500, blue: 0.000)", "colors copy as RGB, HSL and SwiftUI")
        check(ColorPalette.text([orange], notation: .hex, css: true) == ":root {\n  --color-1: #FF8000;\n}" && ColorPalette.image(swatches, notation: .hex)?.width == 480, "the palette copies as CSS and saves as swatches")

        // Searchable PDF: a page that is only a picture gets its words, invisibly, and looks the same.
        func page(_ words: String, width: Int = 1240, height: Int = 1754) -> CGImage {
            let sheet = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            sheet.setFillColor(CGColor(gray: 1, alpha: 1)); sheet.fill(CGRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)
            NSAttributedString(string: words, attributes: [.font: NSFont.systemFont(ofSize: 64, weight: .medium), .foregroundColor: NSColor.black]).draw(at: NSPoint(x: 120, y: CGFloat(height) - 300))
            NSGraphicsContext.restoreGraphicsState()
            return sheet.makeImage()!
        }
        let scanned = PDFDocument(); scanned.insert(PDFPage(image: NSImage(cgImage: page("Quarterly tangerine report"), size: NSSize(width: 595, height: 842)))!, at: 0)
        let scannedURL = dir.appendingPathComponent("scanned.pdf"), searchableURL = dir.appendingPathComponent("searchable.pdf")
        check(scanned.write(to: scannedURL) && (PDFDocument(url: scannedURL)?.page(at: 0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "a scanned page has no text of its own")
        let read = try SearchablePDF.make(scannedURL, to: searchableURL, progress: { _ in })
        let searchable = PDFDocument(url: searchableURL)
        check(read == 1 && (searchable?.page(at: 0)?.string ?? "").contains("tangerine") && !(searchable?.findString("Quarterly", withOptions: .caseInsensitive).isEmpty ?? true), "the scanned page can now be searched: \(searchable?.page(at: 0)?.string ?? "-")")
        let look = { (url: URL) in pixels(PDFRenderer.render(page: PDFDocument(url: url)!.page(at: 0)!, dpi: 36)!) }
        let a = look(scannedURL), b = look(searchableURL)
        check(a.count == b.count && zip(a, b).filter { abs(Int($0) - Int($1)) > 8 }.count < a.count / 100, "the hidden text changes nothing on the page")
        // Scan to PDF: a sheet photographed askew is found, straightened, and saved searchable.
        let photoW = 1600, photoH = 1200
        let desk = CGContext(data: nil, width: photoW, height: photoH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        desk.setFillColor(CGColor(red: 0.25, green: 0.2, blue: 0.15, alpha: 1)); desk.fill(CGRect(x: 0, y: 0, width: photoW, height: photoH))
        let sheetCorners = [CGPoint(x: 420, y: 1080), CGPoint(x: 1220, y: 1040), CGPoint(x: 1260, y: 120), CGPoint(x: 380, y: 160)] // tl, tr, br, bl (bottom-left origin)
        desk.saveGState()
        desk.move(to: sheetCorners[0]); sheetCorners.dropFirst().forEach { desk.addLine(to: $0) }; desk.closePath(); desk.clip()
        let invoice = page("Invoice 2026 citrus", width: 900, height: 1000)
        desk.draw(invoice, in: CGRect(x: 380, y: 120, width: 880, height: 960))
        desk.restoreGState()
        let photo = desk.makeImage()!
        if let quad = DocumentScan.detect(photo) {
            let expected = [CGPoint(x: 420.0 / 1600, y: 1 - 1080.0 / 1200), CGPoint(x: 1220.0 / 1600, y: 1 - 1040.0 / 1200), CGPoint(x: 1260.0 / 1600, y: 1 - 120.0 / 1200), CGPoint(x: 380.0 / 1600, y: 1 - 160.0 / 1200)]
            check(zip(quad.corners, expected).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) < 0.04 }, "the sheet's corners are found: \(quad.corners)")
        } else {
            check(false, "the sheet is found in the photo")
        }
        let flat = DocumentScan.flatten(photo, quad: DocumentScan.Quad(topLeft: CGPoint(x: 420.0 / 1600, y: 1 - 1080.0 / 1200), topRight: CGPoint(x: 1220.0 / 1600, y: 1 - 1040.0 / 1200), bottomRight: CGPoint(x: 1260.0 / 1600, y: 1 - 120.0 / 1200), bottomLeft: CGPoint(x: 380.0 / 1600, y: 1 - 160.0 / 1200)), look: .gray)!
        let flatPixels = pixels(flat)
        check(abs(Double(flat.width) / Double(flat.height) - 0.87) < 0.12 && flatPixels[(5 * flat.width + 5) * 4] > 200, "the sheet comes out straight, its paper white (\(flat.width) × \(flat.height))")
        let scanURL = dir.appendingPathComponent("scan.pdf")
        try DocumentScan.makePDF([flat, flat], size: .a4, searchable: true, to: scanURL, progress: { _ in })
        let scan = PDFDocument(url: scanURL)
        check(scan?.pageCount == 2 && Int(scan?.page(at: 0)?.bounds(for: .mediaBox).width ?? 0) == 595 && (scan?.page(at: 1)?.string ?? "").contains("citrus"), "two A4 pages with their text: \(scan?.page(at: 1)?.string ?? "-")")

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
        // Unzip: a plain archive comes back whole; a malicious one is refused before anything is written.
        let unzipped = try await SafeUnzip.extract(archive)
        check(unzipped.lastPathComponent == "Archive" && (try? String(contentsOf: unzipped.appendingPathComponent("Album/photo.txt"), encoding: .utf8)) == "inside", "unzip unpacks next to the archive into its own folder")
        let albumZip = try await FileAction.zip([zipDir.appendingPathComponent("Album")])
        let albumOut = try await SafeUnzip.extract(albumZip)
        check(albumOut.lastPathComponent == "Album 2" && FileManager.default.fileExists(atPath: albumOut.appendingPathComponent("photo.txt").path), "a single top folder is unpacked as itself, never over the original")
        let evil = dir.appendingPathComponent("evil.zip")
        _ = try await Shell.run("/usr/bin/python3", ["-c", "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w'); z.writestr('../escaped.txt','x'); z.writestr('ok.txt','y'); z.close()", evil.path])
        do {
            _ = try await SafeUnzip.extract(evil)
            check(false, "an archive that climbs out of its folder is refused")
        } catch {
            check(!FileManager.default.fileExists(atPath: dir.deletingLastPathComponent().appendingPathComponent("escaped.txt").path) && !FileManager.default.fileExists(atPath: dir.appendingPathComponent("evil").path), "an archive that climbs out of its folder is refused, nothing written")
        }

        // PDF passwords: protect, refuse a wrong password, unlock with the right one.
        let plainPDF = dir.appendingPathComponent("plain.pdf"), lockedPDF = dir.appendingPathComponent("locked.pdf"), reopened = dir.appendingPathComponent("reopened.pdf")
        let onePage = PDFDocument(); onePage.insert(PDFPage(image: NSImage(cgImage: grey, size: NSSize(width: 400, height: 300)))!, at: 0)
        check(onePage.write(to: plainPDF), "PDF fixture writes")
        try PDFOps.protect(plainPDF, password: "orange", to: lockedPDF)
        check(PDFDocument(url: lockedPDF)?.isLocked == true, "a protected PDF asks for its password")
        do {
            try PDFOps.unlock(lockedPDF, password: "lemon", to: reopened)
            check(false, "a wrong password is refused")
        } catch {
            check(!FileManager.default.fileExists(atPath: reopened.path), "a wrong password is refused")
        }
        try PDFOps.unlock(lockedPDF, password: "orange", to: reopened)
        check(PDFDocument(url: reopened).map { !$0.isLocked && !$0.isEncrypted && $0.pageCount == 1 } == true, "the right password gives a copy that opens freely")
        // The wheel offers what each PDF's state allows.
        check(ToolID.available(for: [plainPDF]).contains(.protectPDF) && !ToolID.available(for: [plainPDF]).contains(.unlockPDF), "a PDF without a password is never offered Remove the password")
        check(ToolID.available(for: [lockedPDF]) == [.unlockPDF] && ToolID.containsLockedPDF([lockedPDF]) && !ToolID.containsLockedPDF([plainPDF]), "a PDF that asks for a password is only offered Remove the password")
        check(ToolID.available(for: [plainPDF, lockedPDF]).isEmpty, "locked and open PDFs together share no tool")
        let restrictedPDF = dir.appendingPathComponent("restricted.pdf")
        if onePage.write(to: restrictedPDF, withOptions: [.ownerPasswordOption: "owner-only"]), let restricted = PDFDocument(url: restrictedPDF), restricted.isEncrypted, !restricted.isLocked {
            check(ToolID.available(for: [restrictedPDF]).contains(.unlockPDF) && ToolID.available(for: [restrictedPDF]).contains(.splitPDF), "a PDF with owner restrictions opens, and can have them removed")
        }

        // Codes: a QR code drawn here is read back, with its link and place.
        let qrFilter = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data("https://github.com/M-U-C-K-A/Open-Tangerine".utf8), "inputCorrectionLevel": "M"])!
        let qrImage = ImageOps.render(qrFilter.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12)))!
        let qrCanvas = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        qrCanvas.setFillColor(CGColor(gray: 1, alpha: 1)); qrCanvas.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        qrCanvas.draw(qrImage, in: CGRect(x: 40, y: 600 - 40 - qrImage.height, width: qrImage.width, height: qrImage.height))
        do {
            let codes = try BarcodeReader.codes(in: qrCanvas.makeImage()!, file: "poster.png")
            check(codes.count == 1 && codes[0].link?.host == "github.com" && codes[0].kind == "QR code", "a QR code is read with its link")
            check(codes.first.map { $0.box.minX < 0.2 && $0.box.minY < 0.25 } == true, "its place is given from the top-left")
        } catch OpenTangerineError.toolFailed(_, let reason) {
            print("BLOCKED Vision barcodes unavailable in this process: \(reason)")
        }

        // Faces: the cover grows around each face, stays inside the picture, and hides only there.
        let grown = FaceBlur.covered(CGRect(x: 100, y: 100, width: 50, height: 60), padding: 0.2, in: CGRect(x: 0, y: 0, width: 400, height: 300))
        check(grown == CGRect(x: 90, y: 88, width: 70, height: 84), "face cover grows by the margin")
        check(FaceBlur.covered(CGRect(x: 380, y: 280, width: 40, height: 40), padding: 0.5, in: CGRect(x: 0, y: 0, width: 400, height: 300)).maxX == 400, "face cover stays inside the picture")
        let boxed = pixels(ImageOps.render(FaceBlur.hide(CIImage(cgImage: corner.isEmpty ? grey : grey), faces: [CGRect(x: 0, y: 200, width: 100, height: 100)], options: FaceBlur.Options(style: .solid, padding: 0)), extent: CGRect(x: 0, y: 0, width: 400, height: 300))!)
        check(boxed[(50 * 400 + 50) * 4] < 20 && boxed[(250 * 400 + 300) * 4] == greyPixels[(250 * 400 + 300) * 4], "hiding covers the face only (Core Image coordinates, origin bottom-left)")
        do {
            _ = try FaceBlur.apply(grey, options: FaceBlur.Options())
            check(false, "a picture without faces is reported")
        } catch OpenTangerineError.invalidInput {
            check(true, "a picture without faces is reported")
        } catch OpenTangerineError.toolFailed(_, let reason) {
            print("BLOCKED Vision faces unavailable in this process: \(reason)")
        }

        let batchNames = BackgroundRemoval.outputURLs(for: [dir.appendingPathComponent("a.jpg"), dir.appendingPathComponent("a.png")]) { $0.deletingLastPathComponent() }
        check(batchNames.map(\.lastPathComponent) == ["a (no background).png", "a (no background) 2.png"], "background removal batch outputs never collide")
        print("Image tool failures: \(failures)")
        if failures > 0 { exit(1) }
    }
}
