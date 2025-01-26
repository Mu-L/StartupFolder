//
//  Settings.swift
//  StartupFolder
//
//  Created by Alin Panaitiu on 24.01.2025.
//

import Defaults
import Foundation
import SwiftUI

enum LabelStyleSetting: String, CaseIterable, Identifiable, Defaults.Serializable {
    case titleOnly
    case titleAndIcon
    case iconOnly

    var id: String { rawValue }

    var text: String {
        switch self {
        case .titleOnly:
            "Title only"
        case .titleAndIcon:
            "Title and Icon"
        case .iconOnly:
            "Icon only"
        }
    }
}

extension View {
    @ViewBuilder
    func labelStyle(_ style: LabelStyleSetting) -> some View {
        switch style {
        case .titleOnly:
            labelStyle(TitleOnlyLabelStyle())
        case .titleAndIcon:
            labelStyle(TitleAndIconLabelStyle())
        case .iconOnly:
            labelStyle(IconOnlyLabelStyle())
        }
    }
}

extension Defaults.Keys {
    static let editorApp = Key<URL>("editorApp", default: URL(fileURLWithPath: "/System/Applications/TextEdit.app"))
    static let labelStyle = Key<LabelStyleSetting>("labelStyle", default: .titleOnly)
    static let startupFolderPath = Key<URL>("startupFolderPath", default: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Startup"))
}
