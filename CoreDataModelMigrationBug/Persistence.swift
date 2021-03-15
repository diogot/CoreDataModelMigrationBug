//
//  Persistence.swift
//  CoreDataModelMigrationBug
//
//  Created by Diogo Tridapalli on 15/03/21.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer
    let migrationModel: MigrationOption = .migrationModel

    init(inMemory: Bool = false) {
        let destModel = NSManagedObjectModel.managedObjectModel(forResource: "CoreDataModelMigrationBug 2",
                                                                in: Bundle.main)
        container = NSPersistentContainer(name: "CoreDataModelMigrationBug", managedObjectModel: destModel)
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            let storeURL = prepareStore(using: "CoreDataModelMigrationBug")

            container.persistentStoreDescriptions.first!.url = storeURL
            container.persistentStoreDescriptions.first!.shouldMigrateStoreAutomatically = false

            let sourceModel = NSManagedObjectModel.managedObjectModel(forResource: "CoreDataModelMigrationBug",
                                                                      in: Bundle.main)
            let migrationFile = Bundle.main.url(forResource: "Model-v1-v2", withExtension: "cdm")!

            let mappingModel: NSMappingModel
            switch migrationModel {
            case .infered:
                mappingModel = try! NSMappingModel.inferredMappingModel(forSourceModel: sourceModel,
                                                                        destinationModel: destModel)
            case .migrationModel:
                mappingModel = NSMappingModel(contentsOf: migrationFile)!
                container.persistentStoreDescriptions.first!.shouldInferMappingModelAutomatically = false
            case .fixedMigrationModel:
                container.persistentStoreDescriptions.first!.shouldInferMappingModelAutomatically = false
                mappingModel = NSMappingModel(contentsOf: migrationFile)!
                var entityMappings = [NSEntityMapping]()
                for mapping in mappingModel.entityMappings {
                    let sourceName = mapping.sourceEntityName!
                    let mappingSourceHash = mapping.sourceEntityVersionHash!
                    let sourceHash = sourceModel.entityVersionHashesByName[sourceName]!
                    if mappingSourceHash != sourceHash, sourceModel.entitiesByName[sourceName]!.canBugMigration() {
                        mapping.sourceEntityVersionHash = sourceHash
                    }
                    let destName = mapping.destinationEntityName!
                    let mappingDestHash = mapping.destinationEntityVersionHash!
                    let destHash = destModel.entityVersionHashesByName[destName]!
                    if mappingDestHash != destHash, destModel.entitiesByName[destName]!.canBugMigration() {
                        mapping.destinationEntityVersionHash = destHash
                    }
                    entityMappings.append(mapping)
                }
                mappingModel.entityMappings = entityMappings
            }

            let manager = NSMigrationManager(sourceModel: sourceModel,
                                             destinationModel: destModel)
            let destination = URL(fileURLWithPath: NSTemporaryDirectory(),
                                  isDirectory: true).appendingPathComponent(UUID().uuidString)

            try! manager.migrateStore(from: storeURL, sourceType: NSSQLiteStoreType, options: nil,
                                     with: mappingModel,
                                     toDestinationURL: destination, destinationType: NSSQLiteStoreType,
                                     destinationOptions: nil)
            try! NSPersistentStoreCoordinator.replaceStore(at: storeURL, withStoreAt: destination)
            try! NSPersistentStoreCoordinator.destroyStore(at: destination)
        }

        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                Typical reasons for an error here include:
                * The parent directory does not exist, cannot be created, or disallows writing.
                * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                * The device is out of space.
                * The store could not be migrated to the current model version.
                Check the error message to determine what the actual problem was.
                */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
    }

    enum MigrationOption {
        case infered
        case migrationModel
        case fixedMigrationModel
    }

}

private func prepareStore(using source: String) -> URL {
    let newFile = UUID().uuidString
    let destination = copy(source: source, destination: newFile, withExtension: ".sqlite")
    _ = copy(source: source, destination: newFile, withExtension: ".sqlite-wal")
    _ = copy(source: source, destination: newFile, withExtension: ".sqlite-shm")

    return destination
}

private func copy(source: String, destination: String, withExtension: String) -> URL {
    let sourceURL = Bundle.main.url(forResource: source, withExtension: withExtension)!
    let destination = URL(fileURLWithPath: NSTemporaryDirectory(),
                          isDirectory: true).appendingPathComponent(destination + withExtension)

    try! FileManager.default.copyItem(at: sourceURL, to: destination)

    return destination
}

private extension NSEntityDescription {
    func canBugMigration() -> Bool {
        properties
            .compactMap { $0 as?  NSDerivedAttributeDescription }
            .contains { $0.attributeType == .dateAttributeType && $0.derivationExpression == NSExpression(format: "now()") }
    }
}

extension NSManagedObjectModel {
    /// Used to find a managed object model based on a model version name.
    ///
    /// - Parameter resource: The model version name to find the model for.
    /// - Returns: The managed object model.
    static func managedObjectModel(forResource resource: String, in bundle: Bundle) -> NSManagedObjectModel {
        let subdirectory = "CoreDataModelMigrationBug.momd"

        var omoURL: URL?
        if #available(iOS 11, *) {
            omoURL = bundle.url(forResource: resource, withExtension: "omo", subdirectory: subdirectory)
        }
        let momURL = bundle.url(forResource: resource, withExtension: "mom", subdirectory: subdirectory)

        guard let url = omoURL ?? momURL else {
            fatalError("missing models")
        }

        guard let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("modelnot loaded")
        }

        return model
    }
}

extension NSPersistentStoreCoordinator {
    /// Convenience method to obtain store metadata.
    ///
    /// - Parameter storeURL: The store URL to obtain metadata for.
    /// - Returns: The store metadata.
    static func metadata(at storeURL: URL) throws -> [String: Any] {
        return try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL,
                                                                           options: nil)
    }

    /// Adds an SQL lite store to the current coordinator with the supplied options
    ///
    /// - Parameters:
    ///   - storeURL: The URL for the store that should be added.
    ///   - options: The store options that should be appliec to the persistent store.
    /// - Returns: The persistent store that was just added to the coordinator.
    func addPersistentStore(at storeURL: URL, options: [AnyHashable: Any]) throws -> NSPersistentStore {
        return try addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)
    }

    /// Removes the store for the provided store URL.
    ///
    /// - Parameter storeURL: The URL to remove the store for.
    static func destroyStore(at storeURL: URL) throws {
        let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        try persistentStoreCoordinator.destroyPersistentStore(at: storeURL, ofType: NSSQLiteStoreType, options: nil)
    }

    /// Replaces one store with the other.
    ///
    /// - Parameters:
    ///   - targetURL: The URL for the store that should be removed.
    ///   - sourceURL: The URL for the store that should be added.
    static func replaceStore(at targetURL: URL, withStoreAt sourceURL: URL) throws {
        let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        try persistentStoreCoordinator.replacePersistentStore(at: targetURL, destinationOptions: nil,
                                                              withPersistentStoreFrom: sourceURL, sourceOptions: nil,
                                                              ofType: NSSQLiteStoreType)
    }
}
