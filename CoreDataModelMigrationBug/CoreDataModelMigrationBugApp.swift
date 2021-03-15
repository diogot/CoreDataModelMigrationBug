//
//  CoreDataModelMigrationBugApp.swift
//  CoreDataModelMigrationBug
//
//  Created by Diogo Tridapalli on 15/03/21.
//

import SwiftUI

@main
struct CoreDataModelMigrationBugApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            NavigationView {
                ContentView()
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
