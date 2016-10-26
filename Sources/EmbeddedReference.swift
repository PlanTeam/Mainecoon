import MongoKitten

public struct EmbeddedInstance: ValueConvertible {
    public var reference: DBRef
    public var projection: Document
    
    public var collection: MongoKitten.Collection {
        return db[self.reference.documentValue["$ref"].string]
    }
    
    public var referencedIdentifier: Value {
        return self.reference.documentValue["$id"]
    }
    
    fileprivate let db: Database
    fileprivate var embedded: Document? = nil
    
    public var embeddedDocument: Document {
        if let embedded = embedded {
            return embedded
        }
        
        do {
            guard let ref = try resolveReference() else {
                return [:]
            }
            
            return ref.makeBsonValue().document
            
        } catch {
            return [:]
        }
    }
    
    public init?(_ document: Document, inDatabase db: Database) {
        guard let embedded = document["embedded"].documentValue, let reference = document["reference"].documentValue, let projection = document["projection"].documentValue else {
            return nil
        }
        
        guard let ref = DBRef(reference, inDatabase: db) else {
            return nil
        }
        
        self.embedded = embedded
        self.projection = projection
        self.db = db
        self.reference = ref
    }
    
    public init(reference: DBRef, withProjection projection: Projection, inDatabase db: Database) throws {
        self.reference = reference
        self.projection = projection.document
        self.db = db
    }
    
    public func makeBsonValue() -> Value {
        return [
            "embedded": ~self.embeddedDocument,
            "reference": self.reference.bsonValue,
            "projection": ~self.projection
        ]
    }
    
    public func resolveReference() throws -> Instance? {
        let collection = self.collection
        
        guard let document = try collection.findOne(matching: "_id" == self.referencedIdentifier) else {
            return nil
        }
        
        let type = try Model(named: collection.name).instanceType
        return try? type.init(document, validatingDocument: true)
    }
}
