import Foundation

struct ArchiveEngine: ConversionEngine {
    func supports(from: FileFormat, to: FileFormat) -> Bool {
        from.category == .archive && to.category == .archive && to != .rar
    }

    func convert(_ request: ConversionRequest) async throws {
        throw OpenTangerineError.invalidInput("Archive conversion is disabled in this trial pending bounded, isolated extraction. Original archives are unchanged.")
    }

    func extract(_ archive: URL, format: FileFormat, into directory: URL) async throws {
        switch format {
        case .zip:
            try await ZipTool.unzip(archive, into: directory)
        case .tar:
            let result = try await Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", directory.path])
            guard result.succeeded else { throw OpenTangerineError.toolFailed("tar", result.stderr) }
        case .gz:
            let name = archive.lastPathComponent.lowercased()
            if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
                let result = try await Shell.run("/usr/bin/tar", ["-xzf", archive.path, "-C", directory.path])
                guard result.succeeded else { throw OpenTangerineError.toolFailed("tar", result.stderr) }
            } else {
                let output = directory.appendingPathComponent(archive.deletingPathExtension().lastPathComponent)
                let result = try await Shell.run("/bin/sh", ["-c", "/usr/bin/gunzip -c \"$0\" > \"$1\"", archive.path, output.path])
                guard result.succeeded else { throw OpenTangerineError.toolFailed("gunzip", result.stderr) }
            }
        case .rar:
            let candidates = ["unar", "unrar", "bsdtar"]
            for tool in candidates {
                guard let path = Shell.which(tool) else { continue }
                let args: [String]
                switch tool {
                case "unar": args = ["-q", "-o", directory.path, archive.path]
                case "unrar": args = ["x", "-y", "-idq", archive.path, directory.path + "/"]
                default: args = ["-xf", archive.path, "-C", directory.path]
                }
                let result = try await Shell.run(path, args)
                if result.succeeded { return }
            }
            let bsdtar = try await Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", directory.path])
            guard bsdtar.succeeded else {
                throw OpenTangerineError.toolFailed("rar", "Install `unar` (`brew install unar`) to extract RAR archives.")
            }
        default:
            throw OpenTangerineError.unsupportedConversion(format, .zip)
        }
    }

    func pack(_ directory: URL, as format: FileFormat, to destination: URL) async throws {
        switch format {
        case .zip:
            try await ZipTool.zip(directory: directory, to: destination)
        case .tar:
            let result = try await Shell.run("/usr/bin/tar", ["-cf", destination.path, "-C", directory.path, "."])
            guard result.succeeded else { throw OpenTangerineError.toolFailed("tar", result.stderr) }
        case .gz:
            let result = try await Shell.run("/usr/bin/tar", ["-czf", destination.path, "-C", directory.path, "."])
            guard result.succeeded else { throw OpenTangerineError.toolFailed("tar", result.stderr) }
        default:
            throw OpenTangerineError.unsupportedConversion(.zip, format)
        }
    }
}

