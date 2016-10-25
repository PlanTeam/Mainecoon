@_exported import MongoKitten
import Foundation

#if os(macOS)
    typealias RegularExpression = NSRegularExpression
#endif

fileprivate var instances = [(InstanceProtocol, Model)]()

public enum MainecoonError: Error {
    case invalidInstanceType
    case invalidInstanceDocument(error: String)
}

public typealias StorageErrorHandler = (Error, Instance)->()

public protocol InstanceProtocol {
    var model: Model { get }
    subscript(key: String) -> Value { get set }
    subscript(reference ref: String) -> Instance? { get set }
    func store() throws
    func remove() throws
    func makeReference() -> DBRef
}

public protocol Instance: InstanceProtocol {
    init(_ document: Document, asType type: Model, validatingDocument validate: Bool) throws
    init(_ document: Document, asType type: Model, projectedBy projection: Projection, validatingDocument validate: Bool) throws
}

public class BasicInstance: Instance {
    internal enum State {
        case partial, whole
    }
    
    var identifier: Value {
        get {
            return self["_id"]
        }
        set {
            self["_id"] = newValue
        }
    }
    
    public required init(_ document: Document, asType type: Model, validatingDocument: Bool = true) throws {
        if validatingDocument, case .invalid(let error) = type.schematics.validate(document) {
            throw MainecoonError.invalidInstanceDocument(error: error)
        }
        
        self.document = document
        self.model = type
        self.state = .whole
    }
    
    public required init(_ document: Document, asType type: Model, projectedBy projection: Projection, validatingDocument: Bool = true) throws {
        if validatingDocument, case .invalid(let error) = type.schematics.validate(document, ignoringFields: projection) {
            throw MainecoonError.invalidInstanceDocument(error: error)
        }
        
        self.document = document
        self.model = type
        self.state = .partial
    }

    var state: State
    var document: Document
    public let model: Model
    public var storeAutomatically = true
    
    public static var storageErrorHandler: StorageErrorHandler = { error, instance in
        print("Error: \"\(error)\". In Instance \(instance)")
    }
    
    public subscript(key: String) -> Value {
        get {
            return document[key]
        }
        set {
            document[key] = newValue
        }
    }
    
    public subscript(reference ref: String) -> Instance? {
        get {
            guard let typeRequirement = self.model.schematics.requirements.first(where: { name, requirement in
                name == ref
            }) else {
                return nil
            }
            
            guard case .reference(let type) = typeRequirement.requirement else {
                return nil
            }
            
            let value = document[ref]
            
            if case .document(let referenceDocument) = value {
                guard let d = try? DBRef(referenceDocument, inDatabase: self.model.collection.database)?.resolve(), let document = d else {
                    return nil
                }
                
                guard let model = try? type.makeModel() else {
                    return nil
                }
                
                return try? type.init(document, asType: model, validatingDocument: true)
            }
            
            return (try? type.findOne(matching: "_id" == self[ref])) ?? nil
        }
        set {
            guard let newValue = newValue else {
                self[ref] = .nothing
                return
            }
            
            self[ref] = DBRef(referencing: newValue["_id"], inCollection: newValue.model.collection).bsonValue
        }
    }
    
    public func store() throws {
        switch state {
        case .whole:
            try model.collection.update(matching: "_id" == self["_id"], to: self.document, upserting: true, multiple: false)
        case .partial:
            try model.collection.update(matching: "_id" == self["_id"], to: ["$set": ~self.document], upserting: true, multiple: false)
        }
        
    }
    
    public func remove() throws {
        try model.collection.remove(matching: "_id" == self["_id"], limitedTo: 1)
    }
    
    deinit {
        guard storeAutomatically else {
            return
        }
        
        do {
            try self.store()
        } catch {
            BasicInstance.storageErrorHandler(error, self)
        }
    }
    
    public func makeReference() -> DBRef {
        return DBRef(referencing: self["_id"], inCollection: self.model.collection)
    }
}

public final class Model {
    public fileprivate(set) var collection: MongoKitten.Collection
    public fileprivate(set) var schematics: Schema
    public fileprivate(set) var name: (singular: String, plural: String)
    public fileprivate(set) var instanceType: Instance.Type
    
    init(named name: (singular: String, plural: String), inCollection collection: MongoKitten.Collection, withSchematics schema: Schema, instanceType: Instance.Type) {
        self.collection = collection
        self.schematics = schema
        self.name = name
        self.instanceType = instanceType
    }
    
    public static func makeModel<T: InstanceProtocol>(typeOf instanceType: T.Type) throws -> Model {
        guard let (_, type) = instances.first(where: { $0.0 is T }) else {
            throw MainecoonError.invalidInstanceType
        }
        
        return Model(named: type.name, inCollection: type.collection, withSchematics: type.schematics, instanceType: type.instanceType)
    }
}

public func registerModel(named name: (singular: String, plural: String), withSchematics schematics: Schema, inDatabase db: Database, instanceType: Instance.Type = BasicInstance.self) -> Model {
    let modelType = Model(named: name, inCollection: db[name.plural], withSchematics: schematics, instanceType: instanceType)
    instances.append((instanceType as! InstanceProtocol, modelType))
    
    return modelType
}
