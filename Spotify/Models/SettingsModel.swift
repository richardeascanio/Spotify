//
//  SettingsModel.swift
//  Spotify
//
//  Created by Richard Ascanio on 4/5/22.
//

import Foundation


struct Section {
    let title: String
    let options: [Option]
}

struct Option {
    let title: String
    let handler: () -> Void
}
