import Foundation

enum ToolArity {
    case single
    case multiple
    case any
}

enum ToolID: String, CaseIterable, Identifiable {
    case compress
    case editMetadata
    case editImage
    case frameImage
    case removeBackground
    case watermarkImage
    case upscaleImage
    case blurFaces
    case translateText
    case transcribeSpeech
    case protectPDF
    case unlockPDF
    case cropImage
    case redactImage
    case resizeImage
    case rotateImage
    case createPDF
    case createCollage
    case trimVideo
    case cropVideo
    case changeVideoSpeed
    case joinVideos
    case videoSnapshots
    case splitVideo
    case redactVideo
    case normalizeAudio
    case audioToVideo
    case trimAudio
    case audioChannels
    case redactAudio
    case mergePDF
    case organizePDF
    case splitPDF
    /// Opened from the File actions wheel (Control), for any files and folders.
    case renameFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compress: return "Compress"
        case .editMetadata: return "Edit metadata"
        case .editImage: return "Edit photo"
        case .frameImage: return "Add a background"
        case .removeBackground: return "Remove background"
        case .watermarkImage: return "Add a watermark"
        case .upscaleImage: return "Upscale image"
        case .blurFaces: return "Hide faces"
        case .translateText: return "Translate"
        case .transcribeSpeech: return "Subtitles from speech"
        case .protectPDF: return "Add a password"
        case .unlockPDF: return "Remove the password"
        case .cropImage: return "Crop image"
        case .redactImage: return "Redact photo"
        case .resizeImage: return "Resize images"
        case .rotateImage: return "Rotate & flip"
        case .createPDF: return "Create a PDF"
        case .createCollage: return "Create a collage"
        case .trimVideo: return "Trim video"
        case .cropVideo: return "Crop video"
        case .changeVideoSpeed: return "Change video speed"
        case .joinVideos: return "Join videos"
        case .videoSnapshots: return "Save video frames"
        case .splitVideo: return "Split video"
        case .redactVideo: return "Redact video"
        case .normalizeAudio: return "Normalize volume"
        case .audioToVideo: return "Audio visualizer"
        case .trimAudio: return "Trim audio"
        case .audioChannels: return "Audio channels"
        case .redactAudio: return "Bleep audio"
        case .mergePDF: return "Merge PDFs"
        case .organizePDF: return "Organize PDF pages"
        case .splitPDF: return "Split PDF"
        case .renameFiles: return "Rename files"
        }
    }

    /// One line on what the tool does, for the notch.
    var summary: String {
        switch self {
        case .compress: return "Makes files smaller, with a target size if you like."
        case .editMetadata: return "Edits or removes tags, camera and location data."
        case .editImage: return "Light, color and detail, with a before and after."
        case .frameImage: return "Puts the picture on a color or image background."
        case .removeBackground: return "Keeps the subject, makes the rest transparent."
        case .watermarkImage: return "Adds a text or logo mark."
        case .upscaleImage: return "Makes pictures ×2 or ×4 bigger, with rebuilt detail if you like."
        case .blurFaces: return "Finds every face and blurs or covers it."
        case .translateText: return "Translates subtitles, text, and the text in pictures."
        case .transcribeSpeech: return "Writes subtitles from what is said."
        case .protectPDF: return "Makes a copy that needs a password to open."
        case .unlockPDF: return "Makes a copy without the password you know."
        case .cropImage: return "Cuts the picture to a ratio or exact size."
        case .redactImage: return "Hides areas with a box, a blur or pixels."
        case .resizeImage: return "Scales pictures by edge, percent or size."
        case .rotateImage: return "Turns pictures a quarter at a time, or mirrors them."
        case .createPDF: return "Makes one PDF, a page per picture."
        case .createCollage: return "Lays pictures out in a grid, row or column."
        case .trimVideo: return "Keeps the part you choose, usually without re-encoding."
        case .cropVideo: return "Cuts the frame to an area."
        case .changeVideoSpeed: return "Speeds a video up or slows it down."
        case .joinVideos: return "Puts several videos end to end in one MP4."
        case .videoSnapshots: return "Saves frames as pictures."
        case .splitVideo: return "Cuts a video into parts."
        case .redactVideo: return "Hides areas of a video, each for a time."
        case .normalizeAudio: return "Evens out loudness to a standard level."
        case .audioToVideo: return "Turns audio into a video with a waveform."
        case .trimAudio: return "Keeps the part you choose, trims silences."
        case .audioChannels: return "Stereo, mono, or swapped channels."
        case .redactAudio: return "Bleeps words out."
        case .mergePDF: return "Joins PDFs into one, in order."
        case .organizePDF: return "Reorders, rotates or removes pages."
        case .splitPDF: return "Cuts a PDF into several files."
        case .renameFiles: return "Renames files from one pattern."
        }
    }

    var progressTitle: String {
        switch self {
        case .compress: return "Compressing"
        case .editMetadata: return "Editing metadata"
        case .editImage: return "Editing photo"
        case .frameImage: return "Adding background"
        case .removeBackground: return "Removing background"
        case .watermarkImage: return "Adding watermark"
        case .upscaleImage: return "Upscaling"
        case .blurFaces: return "Hiding faces"
        case .translateText: return "Translating"
        case .transcribeSpeech: return "Transcribing"
        case .protectPDF: return "Protecting"
        case .unlockPDF: return "Unlocking"
        case .renameFiles: return "Renaming"
        case .cropImage, .cropVideo: return "Cropping"
        case .redactImage, .redactVideo: return "Redacting"
        case .resizeImage: return "Resizing"
        case .rotateImage: return "Rotating"
        case .createPDF: return "Creating PDF"
        case .createCollage: return "Creating collage"
        case .trimVideo, .trimAudio: return "Trimming"
        case .changeVideoSpeed: return "Changing speed"
        case .joinVideos: return "Joining"
        case .videoSnapshots: return "Saving frames"
        case .splitVideo, .splitPDF: return "Splitting"
        case .normalizeAudio: return "Normalizing"
        case .audioToVideo: return "Creating visualizer"
        case .audioChannels: return "Converting channels"
        case .redactAudio: return "Bleeping"
        case .mergePDF: return "Merging"
        case .organizePDF: return "Organizing"
        }
    }

    var radialLabel: String {
        switch self {
        case .compress: return "COMPRESS"
        case .editMetadata: return "METADATA"
        case .editImage: return "EDIT"
        case .frameImage: return "ADD BG"
        case .removeBackground: return "REMOVE BG"
        case .watermarkImage: return "WATERMARK"
        case .upscaleImage: return "UPSCALE"
        case .blurFaces: return "FACES"
        case .translateText: return "TRANSLATE"
        case .transcribeSpeech: return "SUBTITLES"
        case .protectPDF: return "LOCK"
        case .unlockPDF: return "UNLOCK"
        case .renameFiles: return "RENAME"
        case .cropImage, .cropVideo: return "CROP"
        case .redactImage, .redactVideo: return "REDACT"
        case .resizeImage: return "RESIZE"
        case .rotateImage: return "ROTATE"
        case .createPDF: return "PDF"
        case .createCollage: return "COLLAGE"
        case .trimVideo, .trimAudio: return "TRIM"
        case .changeVideoSpeed: return "SPEED"
        case .joinVideos: return "JOIN"
        case .videoSnapshots: return "FRAMES"
        case .splitVideo, .splitPDF: return "SPLIT"
        case .normalizeAudio: return "NORMALIZE"
        case .audioToVideo: return "VISUALIZE"
        case .audioChannels: return "CHANNELS"
        case .redactAudio: return "BLEEP"
        case .mergePDF: return "MERGE"
        case .organizePDF: return "ORGANIZE"
        }
    }

    var symbol: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .editMetadata: return "tag"
        case .editImage: return "slider.horizontal.3"
        case .frameImage: return "photo.artframe"
        case .removeBackground: return "person.and.background.dotted"
        case .watermarkImage: return "signature"
        case .upscaleImage: return "arrow.up.left.and.arrow.down.right.square"
        case .blurFaces: return "face.dashed"
        case .translateText: return "character.bubble"
        case .transcribeSpeech: return "captions.bubble"
        case .protectPDF: return "lock.doc"
        case .unlockPDF: return "lock.open"
        case .renameFiles: return "pencil.line"
        case .cropImage, .cropVideo: return "crop"
        case .redactImage: return "eye.slash"
        case .redactVideo: return "video.slash"
        case .resizeImage: return "arrow.up.left.and.arrow.down.right"
        case .rotateImage: return "rotate.right"
        case .createPDF: return "doc.richtext"
        case .createCollage: return "square.grid.2x2"
        case .trimVideo, .trimAudio: return "scissors"
        case .changeVideoSpeed: return "gauge.with.dots.needle.67percent"
        case .joinVideos: return "link"
        case .videoSnapshots: return "camera.viewfinder"
        case .splitVideo: return "rectangle.split.2x1"
        case .splitPDF: return "doc.on.doc"
        case .normalizeAudio: return "waveform"
        case .audioToVideo: return "waveform.and.magnifyingglass"
        case .audioChannels: return "headphones"
        case .redactAudio: return "speaker.slash"
        case .mergePDF: return "doc.on.doc.fill"
        case .organizePDF: return "rectangle.stack"
        }
    }

    var categories: Set<FormatCategory> {
        switch self {
        case .compress, .editMetadata:
            return [.image, .video, .audio, .document]
        case .renameFiles:
            return Set(FormatCategory.allCases)
        case .watermarkImage, .upscaleImage:
            return [.image]
        case .blurFaces:
            return [.image, .video]
        case .translateText:
            return [.subtitle, .document, .image]
        case .transcribeSpeech:
            return [.audio, .video]
        case .protectPDF, .unlockPDF:
            return [.document]
        case .editImage, .frameImage, .removeBackground, .cropImage, .redactImage, .resizeImage, .rotateImage, .createPDF, .createCollage:
            return [.image]
        case .trimVideo, .cropVideo, .changeVideoSpeed, .joinVideos, .videoSnapshots, .splitVideo, .redactVideo:
            return [.video]
        case .normalizeAudio, .audioToVideo, .trimAudio, .audioChannels, .redactAudio:
            return [.audio]
        case .mergePDF, .organizePDF, .splitPDF:
            return [.document]
        }
    }

    var arity: ToolArity {
        switch self {
        case .compress, .editMetadata, .removeBackground, .watermarkImage, .upscaleImage, .blurFaces, .translateText, .transcribeSpeech, .protectPDF, .unlockPDF, .resizeImage, .rotateImage, .createPDF, .renameFiles: return .any
        case .createCollage, .joinVideos, .mergePDF: return .multiple
        default: return .single
        }
    }

    func applies(to formats: [FileFormat]) -> Bool {
        // Renaming takes any files and folders, so it lives on the File actions wheel.
        guard self != .renameFiles, !formats.isEmpty else { return false }
        let categories = Set(formats.map(\.category))
        guard categories.count == 1, let category = categories.first, self.categories.contains(category) else { return false }
        if category == .document {
            switch self {
            case .mergePDF, .organizePDF, .splitPDF, .editMetadata, .compress, .protectPDF, .unlockPDF:
                guard formats.allSatisfy({ $0 == .pdf }) else { return false }
            case .translateText:
                guard formats.allSatisfy({ $0 == .pdf || $0 == .txt }) else { return false }
            default:
                return false
            }
        }
        if category == .video, formats.contains(.gif), self != .compress, self != .editMetadata { return false }
        switch arity {
        case .single: return formats.count == 1
        case .multiple: return formats.count >= 2
        case .any: return true
        }
    }

    static func available(for formats: [FileFormat]) -> [ToolID] {
        allCases.filter { $0.applies(to: formats) }
    }

    static var total: Int { allCases.count }
}

