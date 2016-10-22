@_exported import MongoKitten
import Foundation

#if os(macOS)
    typealias RegularExpression = NSRegularExpression
#endif

fileprivate var models = [String: ModelType]()

public enum MainecoonError: Error {
    case invalidModelType
    case invalidModelDocument(error: String)
}

public typealias StorageErrorHandler = (Error, Model)->()

public protocol Model {
    var modelType: ModelType { get }
    
    init(_ document: Document, asType type: ModelType) throws
    init(_ document: Document, asType type: ModelType, validatingDocument: Bool) throws
    subscript(key: String) -> Value { get set }
    subscript(reference ref: String) -> Model? { get set }
    func store() throws
    func remove() throws
    func makeReference() -> DBRef
}

public class BasicModel: Model {
    public required init(_ document: Document, asType type: ModelType) throws {
        if case .invalid(let error) = type.schematics.validate(document) {
            throw MainecoonError.invalidModelDocument(error: error)
        }
        
        self.document = document
        self.modelType = type
    }

    var document: Document
    public let modelType: ModelType
    public var storeAutomatically = true
    
    public static var storageErrorHandler: StorageErrorHandler = { error, model in
        print("Error: \"\(error)\". In Model \(model)")
    }
    
    public required init(_ document: Document, asType type: ModelType, validatingDocument: Bool) throws {
        if validatingDocument, case .invalid(let error) = type.schematics.validate(document) {
            throw MainecoonError.invalidModelDocument(error: error)
        }
        
        self.document = document
        self.modelType = type
    }
    
    public subscript(key: String) -> Value {
        get {
            return document[key]
        }
        set {
            document[key] = newValue
        }
    }
    
    public subscript(reference ref: String) -> Model? {
        get {
            guard let typeRequirement = self.modelType.schematics.requirements.first(where: { name, requirement in
                name == ref
            }) else {
                return nil
            }
            
            guard case .reference(let type) = typeRequirement.requirement else {
                return nil
            }
            
            let value = document[ref]
            
            if case .document(let referenceDocument) = value {
                guard let d = try? DBRef(referenceDocument, inDatabase: self.modelType.collection.database)?.resolve(), let document = d else {
                    return nil
                }
                
                return try? type.modelType.init(document, asType: type)
            }
            
            return (try? type.findOne(matching: "_id" == self[ref])) ?? nil
        }
        set {
            guard let newValue = newValue else {
                self[ref] = .nothing
                return
            }
            
            self[ref] = DBRef(referencing: newValue["_id"], inCollection: newValue.modelType.collection).bsonValue
        }
    }
    
    public func store() throws {
        try modelType.collection.update(matching: "_id" == self["_id"], to: self.document, upserting: true, multiple: false)
    }
    
    public func remove() throws {
        try modelType.collection.remove(matching: "_id" == self["_id"], limitedTo: 1)
    }
    
    deinit {
        guard storeAutomatically else {
            return
        }
        
        do {
            try self.store()
        } catch {
            BasicModel.storageErrorHandler(error, self)
        }
    }
    
    public func makeReference() -> DBRef {
        return DBRef(referencing: self["_id"], inCollection: self.modelType.collection)
    }
}

public class ModelType {
    public fileprivate(set) var collection: MongoKitten.Collection
    public fileprivate(set) var schematics: Schema
    public fileprivate(set) var name: (singular: String, plural: String)
    public fileprivate(set) var modelType: Model.Type
    
    init(named name: (singular: String, plural: String), inCollection collection: MongoKitten.Collection, withSchematics schema: Schema, modelType: Model.Type) {
        self.collection = collection
        self.schematics = schema
        self.name = name
        self.modelType = modelType
    }
    
    public init(bySingularName name: String) throws {
        guard let type = models[name] else {
            throw MainecoonError.invalidModelType
        }
        
        self.collection = type.collection
        self.name = type.name
        self.schematics = type.schematics
        self.modelType = type.modelType
    }
    
    public static func makeType(fromSingularName name: String) throws -> ModelType {
        guard let type = models[name] else {
            throw MainecoonError.invalidModelType
        }
        
        return type
    }
    
    public func count(matching query: QueryProtocol) throws -> Int {
        return try self.collection.count(matching: query)
    }
    
    public func findOne(matching query: QueryProtocol) throws -> Model? {
        guard let document = try collection.findOne(matching: query) else {
            return nil
        }
        
        return try modelType.init(document, asType: self)
    }
    
    public func makeEntity(fromDocument document: Document) throws -> Model {
        return try modelType.init(document, asType: self)
    }
    
    public func find(matching query: QueryProtocol) throws -> Cursor<Model> {
        return Cursor(base: try collection.find(matching: query)) {
            try? self.modelType.init($0, asType: self)
        }
    }
}

public func registerModel(named name: (singular: String, plural: String), withSchematics schematics: Schema, inDatabase db: Database, modelType: Model.Type = BasicModel.self) -> ModelType {
    let modelType = ModelType(named: name, inCollection: db[name.plural], withSchematics: schematics, modelType: modelType)
    models[name.singular] = modelType
    
    return modelType
}
