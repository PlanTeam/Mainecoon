import MongoKitten

extension Instance {
    public static func make<T: Instance>(fromDocument document: Document) throws -> T {
        return try T.init(document, validatingDocument: true)
    }
    
    public static func makeModel() throws -> Model {
        return try Model.makeModel(typeOf: Self.self)
    }
    
    public func makeModel() throws -> Model {
        return try Model.makeModel(typeOf: type(of: self).self)
    }
    
    public static func makeCollection() throws -> MongoKitten.Collection {
        return try makeModel().collection
    }
    
    public static func count(matching query: QueryProtocol) throws -> Int {
        return try makeCollection().count(matching: query)
    }
    
    public static func findOne(matching query: QueryProtocol) throws -> Self? {
        guard let document = try makeCollection().findOne(matching: query) else {
            return nil
        }
        
        return try Self.init(document, validatingDocument: true)
    }
    
    public static func find(matching query: QueryProtocol) throws -> Cursor<Self> {
        return Cursor(base: try makeCollection().find(matching: query)) {
            try? Self.init($0, validatingDocument: true)
        }
    }
    
    public static func find(matching query: Document? = nil) throws -> Cursor<Self> {
        return Cursor(base: try makeCollection().find(matching: query)) {
            try? Self.init($0, validatingDocument: true)
        }
    }
    
    public static func findOne(matching query: QueryProtocol, projecting projection: Projection) throws -> Self? {
        guard let document = try makeCollection().findOne(matching: query, projecting: projection) else {
            return nil
        }
        
        return try Self.init(document, projectedBy: projection, validatingDocument: true)
    }
    
    public static func find(matching query: QueryProtocol, projecting projection: Projection) throws -> Cursor<Self> {
        return Cursor(base: try makeCollection().find(matching: query, projecting: projection)) {
            try? Self.init($0, projectedBy: projection, validatingDocument: true)
        }
    }
    
    public static func find(matching query: Document? = nil, projecting projection: Projection) throws -> Cursor<Self> {
        return Cursor(base: try makeCollection().find(matching: query, projecting: projection)) {
            try? Self.init($0, projectedBy: projection, validatingDocument: true)
        }
    }
}
