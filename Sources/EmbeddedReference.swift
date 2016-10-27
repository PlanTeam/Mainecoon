import MongoKitten

/// An EmbeddedInstance is a mix of a DBRef and an embedded projection of that referenced Instance
public struct EmbeddedInstance: ValueConvertible {
    /// References to the Instance
    public var reference: DBRef
    
    /// The projection used to 
    public var projection: BSONDocument
    
    public var collection: MongoKitten.Collection {
        return db[self.reference.documentValue["$ref"].string]
    }
    
    public var referencedIdentifier: Value {
        return self.reference.documentValue["$id"]
    }
    
    fileprivate let db: Database
    fileprivate var embedded: BSONDocument? = nil
    
    public var embeddedDocument: BSONDocument {
        if let embedded = embedded {
            return embedded
        }
        
        do {
            guard let ref = try resolveReference() else {
                return [:]
            }
            
            return BSONDocument(ref.makeBsonValue().document)
            
        } catch {
            return [:]
        }
    }
    
    public init?(_ document: BSONDocument, inDatabase db: Database) {
        guard let embedded = document["embedded"] as? BSON.Document, let reference = document["reference"] as? BSON.Document, let projection = document["projection"] as? BSON.Document else {
            return nil
        }
        
        guard let ref = DBRef(reference, inDatabase: db) else {
            return nil
        }
        
        self.embedded = BSONDocument(embedded)
        self.projection = BSONDocument(projection)
        self.db = db
        self.reference = ref
    }
    
    public init(reference: DBRef, withProjection projection: Projection, inDatabase db: Database) throws {
        self.reference = reference
        self.projection = BSONDocument(projection.document)
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
        return try? type.init(BSONDocument(document), validatingDocument: true)
    }
}
