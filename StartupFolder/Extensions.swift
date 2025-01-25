//
//  Extensions.swift
//  StartupFolder
//
//  Created by Alin Panaitiu on 25.01.2025.
//

import Foundation
import Lowtech

extension URL {
    func containsByte(_ byte: UInt8) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: self) else {
            return false
        }
        defer { try? fileHandle.close() }

        do {
            var data = try fileHandle.read(upToCount: 16 * 1024)
            while data != nil {
                if let data, data.contains(byte) {
                    return true
                }
                data = try fileHandle.read(upToCount: 16 * 1024)
            }
        } catch {
            log.error("Failed to read file \(path): \(error)")
        }

        return false
    }

    func isDir() -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    func isExecutable() -> Bool {
        FileManager.default.isExecutableFile(atPath: path) && !isDir()
    }
}
