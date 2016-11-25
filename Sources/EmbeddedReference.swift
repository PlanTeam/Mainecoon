import MongoKitten

/// An EmbeddedInstance is a mix of a DBRef and an embedded projection of that referenced Instance
public struct EmbeddedInstance: ValueConvertible {
    /// References to the Instance
    public var reference: DBRef
    
    /// The projection used to 
    public var projection: Document
    
    /// The collection that this referred Instance resides in
    public var collection: MongoKitten.Collection {
        return db[self.reference.documentValue["$ref"]?.string ?? ""]
    }
    
    /// The identifier that's being referred to
    public var referencedIdentifier: ValueConvertible {
        return self.reference.documentValue["$id"] ?? Null()
    }
    
    /// The database that this reference resides in
    fileprivate let db: Database
    
    /// The embedded Document that's a projection of the full one
    fileprivate var embedded: Document? = nil
    
    /// The embedded Document that's a projection of the full one
    public var embeddedDocument: Document {
        if let embedded = embedded {
            return embedded
        }
        
        do {
            guard let ref = try resolveReference() else {
                return [:]
            }
            
            return ref.makeBSONPrimitive() as? Document ?? [:]
            
        } catch {
            return [:]
        }
    }
    
    /// Initializes an EmbeddedInstance from a Document and the database this resides in
    public init?(_ document: Document, inDatabase db: Database) {
        guard let embedded = document["embedded"] as? BSON.Document, let reference = document["reference"] as? BSON.Document, let projection = document["projection"] as? BSON.Document else {
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
    
    /// Initializes an EmbeddedInstance from a reference, projection and the database this resides in
    public init(reference: DBRef, withProjection projection: Projection, inDatabase db: Database) throws {
        self.reference = reference
        self.projection = projection.document
        self.db = db
    }
    
    /// Returns the Document Value representation of this EmbeddedInstance
    public func makeBSONPrimitive() -> BSONPrimitive {
        return [
            "embedded": self.embeddedDocument,
            "reference": self.reference,
            "projection": self.projection
        ] as Document
    }
    
    /// Resolves this EmbeddedInstance to a full Instance that's not just a projection
    public func resolveReference() throws -> Instance? {
        let collection = self.collection
        
        guard let document = try collection.findOne(matching: "_id" == self.referencedIdentifier) else {
            return nil
        }
        
        let type = try Model(named: collection.name).instanceType
        return try? type.init(document, validatingDocument: true, isNew: false)
    }
}
