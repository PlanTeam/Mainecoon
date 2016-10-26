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
    func store() throws
    func remove() throws
    func makeReference() -> DBRef
}

public protocol Instance: InstanceProtocol, ValueConvertible {
    init(_ document: Document, validatingDocument validate: Bool) throws
    init(_ document: Document, projectedBy projection: Projection, validatingDocument validate: Bool) throws
}

open class BasicInstance: Instance {
    public func makeBsonValue() -> Value {
        return ~self.document
    }
    
    public static func makeType() -> BasicInstance.Type {
        return BasicInstance.self
    }

    internal enum State {
        case partial, whole
    }
    
    var identifier: Value {
        get {
            return self.document["_id"]
        }
        set {
            self.document["_id"] = newValue
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
    
    public func getProperty(_ key: String) -> Value {
        return document[key]
    }
    
    public func setProperty(_ key: String, toValue newValue: Value) {
        document[key] = newValue
    }
    
    public func getReference(_ ref: String) throws -> Instance? {
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
            guard let document = try DBRef(referenceDocument, inDatabase: self.model.collection.database)?.resolve() else {
                return nil
            }
            
            return try type.init(document, validatingDocument: true)
        }
        
        return try type.findOne(matching: "_id" == self.document[ref])
    }
    
    public func setProperty(_ key: String, toReferenceOf newValue: BasicInstance) {
        document[key] = DBRef(referencing: newValue.identifier, inCollection: newValue.model.collection).bsonValue
    }
    
    public func getEmbeddedReference(_ key: String) -> EmbeddedInstance? {
        return EmbeddedInstance(self.document[key].document, inDatabase: self.model.collection.database)
    }
    
    public func setEmbeddedReference(_ key: String, toReferenceOf instance: Instance, withProjection projection: Projection) throws {
        let embedded = try EmbeddedInstance(reference: instance.makeReference(), withProjection: projection, inDatabase: self.model.collection.database)
        
        self.document[key] = ~embedded
    }
    
    public func store() throws {
        if self.identifier == .nothing || self.identifier == .null {
            self.identifier = ~ObjectId()
        }
        
        switch state {
        case .whole:
            try model.collection.update(matching: "_id" == self.identifier, to: self.document, upserting: true, multiple: false)
        case .partial:
            try model.collection.update(matching: "_id" == self.identifier, to: ["$set": ~self.document], upserting: true, multiple: false)
        }
        
    }
    
    public func remove() throws {
        try model.collection.remove(matching: "_id" == self.identifier, limitedTo: 1)
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
        return DBRef(referencing: self.identifier, inCollection: self.model.collection)
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
    
    public convenience init(named name: String, plural: Bool = true) throws {
        for (_, model) in instances {
            let referenceName = plural ? model.name.plural : model.name.singular
            
            if referenceName == name {
                self.init(named: model.name, inCollection: model.collection, withSchematics: model.schematics, instanceType: model.instanceType)
                return
            }
        }
        
        throw MainecoonError.invalidInstanceType
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
public func registerModel<T: Instance>(named name: (singular: String, plural: String), withSchematics schematics: Schema, inDatabase db: Database, instanceType: T.Type) throws -> Model {
    let modelType = Model(named: name, inCollection: db[name.plural], withSchematics: schematics, instanceType: T.self as Instance.Type)
    
    try modelType.collection.modify(flags: [
        "validator": schematics.makeBsonValue()
        ])
    
    instances.append((T.self as InstanceProtocol.Type, modelType))
    
    return modelType
}
