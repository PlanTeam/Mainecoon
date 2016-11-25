@_exported import MongoKitten
import Foundation
import BSON

#if os(macOS)
    public typealias RegularExpression = NSRegularExpression
#endif

/// A record of all registered instance types with their associated model
fileprivate var instances = [(InstanceProtocol.Type, Model)]()

/// All errors that can occur. Very poorly set up
public enum MainecoonError: Error {
    /// There is no Model found for this Instance.Type. This is usally because you didn't register a Model
    case invalidInstanceType
    
    /// Failed to initialize the Instance. Details in the error String
    case invalidInstanceDocument(error: String)
}

/// A definition for a handler closure for instance storage errors
public typealias StorageErrorHandler = (Error, Instance, Bool)->()

/// Anything conforming to this will be an instance
public protocol InstanceProtocol {
    /// Stores the instance to it's collection
    func store() throws
    
    /// Removes the instance from it's collection
    func remove() throws
    
    /// Makes a reference to this Instance so that it can be referred to from another database
    func makeReference() -> DBRef
}

/// Anything conforming to this protocol is an instance as well as convertible to a Value so that it can be embedded inside a Document
/// Anything conforming to this protocol will additionally be initializable by means of a Document, (optionally) a Projection and a boolean indicating that the input Document should be validated
public protocol Instance: InstanceProtocol, ValueConvertible {
    /// Initializes a whole instance
    ///
    /// - parameter document: The Document to initialize this Instance with
    /// - parameter validate: When true, we'll validate the input before initializing this Instance
    init(_ document: Document, validatingDocument validate: Bool, isNew: Bool) throws
    
    /// Initializes a partial instance
    ///
    /// - parameter document: The Document to initialize this Instance with
    /// - parameter projection: The Projection to use when validating the Document. We can only validate the projected variables.
    /// - parameter validate: When true, we'll validate the input before initializing this Instance
    init(_ document: Document, projectedBy projection: Projection, validatingDocument validate: Bool, isNew: Bool) throws
    
    /// Initializes a whole instance by looking up the id in the collection
    init(fromIdentifier id: ValueConvertible) throws
    
    /// Initializes a whole instance by looking up the id in the collection projecting provided keys
    init(fromIdentifier id: ValueConvertible, projectedBy projection: Projection) throws
}

/// Any Model registered as a BasicInstance or subclassed from the Basic Instnce will have all base functionality and bloat taken care of.
///
/// This means that all CRUD operations, partial and whole initializers as well as additional helper functions will be availale to you on your Instance.
///
/// Additionally we'll automatically store changes to the database when the Instance is not referred to anymore.
///
/// Subclasses of BasicInstance can be enhanced by adding getter and setter variables to interact with the object more naturally. No additional implementation is necessary but may improve developer productivity and experience
open class BasicInstance: Instance {
    /// Initializes a whole instance by looking up the id in the collection
    public required init(fromIdentifier id: ValueConvertible) throws {
        self.document = [:]
        self.state = .whole
        self.isNew = false
        self.model = try makeModel()
        
        let document = try model.collection.findOne(matching: "_id" == id) ?? [:]
        
        if case .invalid(let error) = self.model.schematics.validate(document) {
            throw MainecoonError.invalidInstanceDocument(error: error)
        }
        
        self.document = document
    }
    
    /// Initializes a partial instance by looking up the id in the collection
    public required init(fromIdentifier id: ValueConvertible, projectedBy projection: Projection) throws {
        self.document = [:]
        self.state = .partial
        self.isNew = false
        self.model = try makeModel()
        
        let document = try model.collection.findOne(matching: "_id" == id, projecting: projection) ?? [:]
        
        if case .invalid(let error) = self.model.schematics.validate(document, validatingFields: projection) {
            throw MainecoonError.invalidInstanceDocument(error: error)
        }
        
        self.document = document
    }
    
    /// Converts this Instance to a Value so that it can be embedded in a Document
    public func makeBSONPrimitive() -> BSONPrimitive {
        return self.document
    }
    
    /// Used to keep track of the state that this BasicInstance has been initialized with.
    /// Used to change the method of storagee
    internal enum State {
        case partial, whole
    }
    
    /// The identifier of this Instance. Usually but not necessarily an ObjectId
    public private(set) var identifier: ValueConvertible {
        get {
            if let id = self.document["_id"] {
                return id
            }
            
            let id = ObjectId()
            self.document["_id"] = id
            return id
        }
        set {
            self.mutatedFields["_id"] = true
            self.document["_id"] = newValue
        }
    }
    
    /// Initializes a whole instance
    ///
    /// - parameter document: The Document to initialize this Instance with
    /// - parameter validate: When true, we'll validate the input before initializing this Instance
    public required init(_ document: Document, validatingDocument: Bool = true, isNew: Bool = true) throws {
        self.document = document
        self.state = .whole
        self.isNew = isNew
        self.model = try makeModel()
        
        if validatingDocument, case .invalid(let error) = self.model.schematics.validate(document) {
            throw MainecoonError.invalidInstanceDocument(error: error)
        }
    }
    
    /// Initializes a partial instance
    ///
    /// - parameter document: The Document to initialize this Instance with
    /// - parameter projection: The Projection to use when validating the Document. We can only validate the projected variables.
    /// - parameter validate: When true, we'll validate the input before initializing this Instance
    public required init(_ document: Document, projectedBy projection: Projection, validatingDocument: Bool = true, isNew: Bool = true) throws {
        self.document = document
        self.state = .partial
        self.isNew = isNew
        self.model = try makeModel()
        
        if case .invalid(let error) = self.model.schematics.validate(document, validatingFields: projection) {
            throw MainecoonError.invalidInstanceDocument(error: error)
        }
    }
    
    /// The current state of this Instance
    var state: State
    
    private var isNew: Bool
    
    private var mutatedFields = Document()
    
    /// The underlying Document type that we use for keeping track of references, Embedded Instances and normal boring variables
    public private(set) var document: Document
    
    /// The Model that's bound to this Instance. Needs to be set by registering this Instance to a Schema, name etc.
    var model: Model! = nil
    
    /// When true, we'll store this Instance to the collection on deinitializing the Instance from memory
    public var storeAutomatically = true
    
    /// Will be executed when an error occured when storing the instance. This includes the deinitializer.
    public static var storageErrorHandler: StorageErrorHandler = { error, instance, deinitializing in
        print("Error: \"\(error)\". In Instance \(instance)")
    }
    
    /// Returns the Document for the given property or `nil` when it's not of this type
    ///
    /// Accessing subproperties can be done by comma separating the key parts
    ///
    /// I.E.: `let subsubproperty = instance.getProperty(forKey: "subdocument", "subsubdocument", "property")`
    public func getProperty(forKey key: String...) -> Document? {
        return document[key] as? Document ?? [:]
    }
    
    /// Returns the Foundation.Date for the given property or `nil` when it's not of this type
    ///
    /// Accessing subproperties can be done by comma separating the key parts
    ///
    /// I.E.: `let subsubproperty = instance.getProperty(forKey: "subdocument", "subsubdocument", "property")`
    public func getProperty(forKey key: String...) -> Date? {
        return document[key] as? Date
    }
    
    /// Returns the Foundation.Data for the given property or `nil` when it's not of this type
    ///
    /// Accessing subproperties can be done by comma separating the key parts
    ///
    /// I.E.: `let subsubproperty = instance.getProperty(forKey: "subdocument", "subsubdocument", "property")`
    public func getProperty(forKey key: String...) -> Data? {
        return document[key] as? Data
    }
    
    /// Returns the ObjectId for the given property or `nil` when it's not of this type
    ///
    /// Accessing subproperties can be done by comma separating the key parts
    ///
    /// I.E.: `let subsubproperty = instance.getProperty(forKey: "subdocument", "subsubdocument", "property")`
    public func getProperty(forKey key: String...) -> ObjectId? {
        return document[key] as? ObjectId
    }
    
    /// Returns the Bool for the given property or `nil` when it's not of this type
    ///
    /// Accessing subproperties can be done by comma separating the key parts
    ///
    /// I.E.: `let subsubproperty = instance.getProperty(forKey: "subdocument", "subsubdocument", "property")`
    public func getProperty(forKey key: String...) -> Bool? {
        return document[key] as? Bool
    }
    
    /// Returns the Int for the given property or `nil` when it's not of this type
    ///
    /// Accessing subproperties can be done by comma separating the key parts
    ///
    /// I.E.: `let subsubproperty = instance.getProperty(forKey: "subdocument", "subsubdocument", "property")`
    public func getProperty(forKey key: String...) -> Int? {
        return document[key]?.int
    }
    
    /// Returns the String for the given property or `nil` when it's not of this type
    ///
    /// Accessing subproperties can be done by comma separating the key parts
    ///
    /// I.E.: `let subsubproperty = instance.getProperty(forKey: "subdocument", "subsubdocument", "property")`
    public func getProperty(forKey key: String...) -> String? {
        return document[key] as? String
    }
    
    /// Sets the Value for the given property.
    ///
    /// Setting subproperties can be done by comma separating the key parts
    ///
    /// I.E.: `instance.setProperty(toValue: true, forKey: "subdocument", "subsubdocument", "property")`
    public func setProperty(toValue newValue: ValueConvertible?, forKey key: String...) {
        self.mutatedFields[key] = true
        document[key] = newValue
    }
    
    /// Gets and resolves a reference for a key
    ///
    /// The key parts are comma separated for accessing sublayers of the Document
    ///
    /// It's recommended to cast this Instance to the related InstanceType.
    ///
    /// I.E.: `user.getReference(forKey: "subdocument", "group") as? Group`
    public func getReference(forKey ref: String...) throws -> Instance? {
        guard let typeRequirement = self.model.schematics.requirements.first(where: { name, requirement in
            name == ref.joined(separator: ".")
        }) else {
            return nil
        }
        
        guard case .reference(let type) = typeRequirement.requirement else {
            return nil
        }
        
        guard let value = document[ref] else {
            return nil
        }
        
        if let referenceDocument = value as? BSON.Document {
            guard let document = try DBRef(referenceDocument, inDatabase: self.model.collection.database)?.resolve() else {
                return nil
            }
            
            return try type.init(document, validatingDocument: true, isNew: false)
        }
        
        return try type.findOne(matching: "_id" == value)
    }
    
    /// Creates a reference to the provided instance at the position of the key
    ///
    /// The key parts are comma separated for accessing sublayers of the Document
    ///
    /// I.E.: `user.setReference(toReferenceOf: userGroup, forKey: "subdocument", "group")`
    public func setReference(toReferenceOf newValue: BasicInstance, forKey key: String...) {
        self.mutatedFields[key] = true
        document[key] = DBRef(referencing: newValue.identifier, inCollection: newValue.model.collection)
    }
    
    /// Ges the EmbeddedInstance from the given key position. Will return `nil` if none is found
    ///
    /// The key parts are comma separated for accessing sublayers of the Document
    ///
    /// I.E.: `user.getEmbeddedInstance(forKey key: "subdocument", "group")`
    public func getEmbeddedInstance(forKey key: String...) -> EmbeddedInstance? {
        return EmbeddedInstance(self.document[key] as? Document ?? [:], inDatabase: self.model.collection.database)
    }
    
    /// Ges the EmbeddedInstance from the given key position. Will return `nil` if none is found
    ///
    /// The key parts are comma separated for accessing sublayers of the Document
    ///
    /// I.E.: `user.getEmbeddedInstance(forKey key: "subdocument", "group")`
    public func setEmbeddedInstance(toReferenceOf instance: Instance, withProjection projection: Projection, forKey key: String...) throws {
        let embedded = try EmbeddedInstance(reference: instance.makeReference(), withProjection: projection, inDatabase: self.model.collection.database)
        
        self.mutatedFields[key] = true
        
        self.document[key] = embedded
    }
    
    /// Stores this Instance tot he collection
    public func store() throws {
        try self.store(fields: self.mutatedFields)
    }
    
    /// Stores this Instance to the collection
    /// Updates only the provided field keys
    ///
    /// Partial Instances will only update the projected values
    public func store(fields: Document) throws {
        if self.identifier is Null {
            self.identifier = ObjectId()
        }
        
        if isNew {
            try model.collection.insert(self.document)
            isNew = false
            return
        }
        
        var setDocument = Document()
        var unsetDocument = Document()
        
        for key in fields.flattened().keys {
            if let value = self.document[key] {
                setDocument[key] = value
            } else {
                unsetDocument[key] = ""
            }
        }
        
        var updateDocument = [:] as Document
        
        if setDocument.count > 0 {
            updateDocument["$set"] = setDocument
        }
        
        if unsetDocument.count > 0 {
            updateDocument["$unset"] = unsetDocument
        }
                
        try model.collection.update(matching: "_id" == self.identifier, to: updateDocument)
    }

    
    /// Removes this Instance from the collection
    ///
    /// Will prevent automatic insertion on deinitializing
    public func remove() throws {
        try model.collection.remove(matching: "_id" == self.identifier, limitedTo: 1)
        
        self.storeAutomatically = false
    }
    
    deinit {
        guard storeAutomatically && self.model != nil else {
            return
        }
        
        do {
            try self.store()
        } catch {
            BasicInstance.storageErrorHandler(error, self, true)
        }
    }
    
    /// Makes a DBRef to this Instance
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
    
    /// Returns a Model that's related to te provided type. Will throw when there's no registered type
    public static func makeModel<T: Instance>(typeOf instanceType: T.Type) throws -> Model {
        for (type, model) in instances {
            if type == instanceType {
                return Model(named: model.name, inCollection: model.collection, withSchematics: model.schematics, instanceType: model.instanceType)
            }
        }
        
        throw MainecoonError.invalidInstanceType
    }
}

/// Registeres a model under a provided name. The plural name will be used for the collection name. Names should be unique and might cause errors when they're not.
///
/// The provided schematics - or `Schama` - will be used to validate the collection Documents and any input that's used to instantiate an Instance of this Model
///
/// The provded database will be where the collection of this Model resides.
///
/// The instanceType will be where you can provide an `Instance.Type` that'll be used to initialize your Instances for this Model.
///
/// This Instance is not defaulted. But Mainecoon supports BasicInstance by default.
///
/// We recommend subclassing BasicInstance and registering the subclass
///
/// - returns: The associated Model that's been created. Can be discarted 99% of the time
@discardableResult
public func registerModel<T: Instance>(named name: (singular: String, plural: String), withSchematics schematics: Schema, inDatabase db: Database, instanceType: T.Type) throws -> Model {
    let modelType = Model(named: name, inCollection: db[name.plural], withSchematics: schematics, instanceType: T.self as Instance.Type)
    
    _ = try? modelType.collection.modify(flags: [
        "validator": schematics
        ])
    
    instances.append((T.self as InstanceProtocol.Type, modelType))
    
    return modelType
}
