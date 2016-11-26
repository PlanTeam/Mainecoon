import MongoKitten
import Reflection

public enum ReflectionError: Error {
    case missingRequiredValue(key: String)
}

public protocol DocumentRepresentable {
    func makeDocument() -> Document
}

public protocol ReflectedDocumentInstance: class, Instance, DocumentRepresentable {
    /// The identifier of this Instance. Usually but not necessarily an ObjectId
    var identifier: ValueConvertible { get set }
    var model: Model! { get set }
    
    init()
}

extension ReflectedDocumentInstance {
    public init(fromIdentifier id: ValueConvertible) throws {
        self.init()
        
        self.model = try makeModel()
        
        guard let document = try model.collection.findOne(matching: "_id" == id) else {
            throw MainecoonError.instanceNotFound(withIdentifier: id)
        }
        
        if case .invalid(let reason) = self.model.schematics.validate(document) {
            throw MainecoonError.invalidInstanceDocument(error: reason)
        }
        
        self.identifier = document["_id"] ?? ObjectId()
        
        for property in try properties(self) {
            if property.key == "identifier" || property.key == "model" {
                continue
            }
            
            guard let value = document[raw: property.key] else {
                throw ReflectionError.missingRequiredValue(key: property.key)
            }
            
            guard property.value is ValueConvertible else {
                continue
            }
            
            switch property.value {
            case is Int:
                if let value = value.int {
                    try set(value, key: property.key, for: self)
                }
            case is Int32:
                if let value = value.int32 {
                    try set(value, key: property.key, for: self)
                }
            case is Int64:
                if let value = value.int64 {
                    try set(value, key: property.key, for: self)
                }
            default:
                try set(value, key: property.key, for: self)
            }
        }
    }
    
    /// Initializes a whole instance
    ///
    /// - parameter document: The Document to initialize this Instance with
    /// - parameter validate: When true, we'll validate the input before initializing this Instance
    public init(_ document: Document, validatingDocument validate: Bool, isNew: Bool) throws {
        self.init()
        
        self.model = try makeModel()
        
        if case .invalid(let reason) = self.model.schematics.validate(document) {
            throw MainecoonError.invalidInstanceDocument(error: reason)
        }
        
        self.identifier = document["_id"] ?? ObjectId()
        
        for property in try properties(self) {
            if property.key == "identifier" || property.key == "model" {
                continue
            }
            
            guard let value = document[raw: property.key] else {
                throw ReflectionError.missingRequiredValue(key: property.key)
            }
            
            
            guard property.value is ValueConvertible else {
                continue
            }
            
            switch property.value {
            case is Int:
                if let value = value.int {
                    try set(value, key: property.key, for: self)
                }
            case is Int32:
                if let value = value.int32 {
                    try set(value, key: property.key, for: self)
                }
            case is Int64:
                if let value = value.int64 {
                    try set(value, key: property.key, for: self)
                }
            default:
                try set(value, key: property.key, for: self)
            }
        }
    }
    
    /// Stores this Instance to the collection
    public func store() throws {
        try self.model.collection.update(matching: "_id" == identifier, to: self.makeDocument(), upserting: true)
    }
    
    public func remove() throws {
        try self.model.collection.remove(matching: "_id" == identifier)
    }
    
    /// Makes a DBRef to this Instance
    public func makeReference() -> DBRef {
        return DBRef(referencing: self.identifier, inCollection: self.model.collection)
    }
    
    func makeDocument() -> Document {
        var document = Document()
        
        do {
            for property in try properties(self) {
                document[raw: property.key] = property.value as? ValueConvertible
            }
        } catch {
            return [:] as Document
        }
        
        return document
    }
    
    /// Initializes a whole instance by looking up the id in the collection
    public func makeBSONPrimitive() -> BSONPrimitive {
        return makeDocument()
    }
}
