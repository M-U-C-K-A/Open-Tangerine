import AppKit
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
        let batchNames = BackgroundRemoval.outputURLs(for: [dir.appendingPathComponent("a.jpg"), dir.appendingPathComponent("a.png")]) { $0.deletingLastPathComponent() }
        check(batchNames.map(\.lastPathComponent) == ["a (no background).png", "a (no background) 2.png"], "background removal batch outputs never collide")
        print("Image tool failures: \(failures)")
        if failures > 0 { exit(1) }
    }
}
