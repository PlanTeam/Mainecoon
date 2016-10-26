@_exported import MongoKitten
import Foundation

#if os(macOS)
    typealias RegularExpression = NSRegularExpression
#endif

fileprivate var instances = [(InstanceProtocol.Type, Model)]()

public enum MainecoonError: Error {
    case invalidInstanceType
    case invalidInstanceDocument(error: String)
}

public typealias StorageErrorHandler = (Error, Instance)->()

public protocol InstanceProtocol {
    subscript(key: String) -> Value { get set }
    subscript(reference ref: String) -> Instance? { get set }
    func store() throws
    func remove() throws
    func makeReference() -> DBRef
}

public protocol Instance: InstanceProtocol {
    init(_ document: Document, validatingDocument validate: Bool) throws
    init(_ document: Document, projectedBy projection: Projection, validatingDocument validate: Bool) throws
}

open class BasicInstance: Instance {
    public static func makeType() -> BasicInstance.Type {
        return BasicInstance.self
    }

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
    
    public required init(_ document: Document, validatingDocument: Bool = true) throws {
        self.document = document
        self.state = .whole
        self.model = try makeModel()
        
        if validatingDocument, case .invalid(let error) = self.model.schematics.validate(document) {
            throw MainecoonError.invalidInstanceDocument(error: error)
        }
    }
    
    public required init(_ document: Document, projectedBy projection: Projection, validatingDocument: Bool = true) throws {
        self.document = document
        self.state = .partial
        self.model = try makeModel()
        
        if validatingDocument, case .invalid(let error) = self.model.schematics.validate(document, ignoringFields: projection) {
            throw MainecoonError.invalidInstanceDocument(error: error)
        }
    }
    
    var state: State
    public private(set) var document: Document
    var model: Model! = nil
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
                
                return try? type.init(document, validatingDocument: true)
            }
            
            return (try? type.findOne(matching: "_id" == self[ref])) ?? nil
        }
        set {
            guard let newValue = newValue else {
                self[ref] = .nothing
                return
            }
            
            guard let model = try? newValue.makeModel() else {
                return
            }
            
            self[ref] = DBRef(referencing: newValue["_id"], inCollection: model.collection).bsonValue
        }
    }
    
    public func store() throws {
        if self["_id"] == .nothing || self["_id"] == .null {
            self["_id"] = ~ObjectId()
        }
        
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
        guard storeAutomatically && self.model != nil else {
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
    
    public static func makeModel<T: Instance>(typeOf instanceType: T.Type) throws -> Model {
        for (type, model) in instances {
            if type == instanceType {
                return Model(named: model.name, inCollection: model.collection, withSchematics: model.schematics, instanceType: model.instanceType)
            }
        }
        
        throw MainecoonError.invalidInstanceType
    }
}

@discardableResult
public func registerModel<T: Instance>(named name: (singular: String, plural: String), withSchematics schematics: Schema, inDatabase db: Database, instanceType: T.Type) -> Model {
    let modelType = Model(named: name, inCollection: db[name.plural], withSchematics: schematics, instanceType: T.self as Instance.Type)
    instances.append((T.self as InstanceProtocol.Type, modelType))
    
    return modelType
}
