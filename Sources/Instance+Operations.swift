import MongoKitten

/// Adds support for CRUD operations on Instances
extension Instance {
    /// Creates an instance of the Instance from a Document
    public static func make<T: Instance>(fromDocument document: Document) throws -> T {
        return try T.init(document, validatingDocument: true)
    }
    
    /// Creates a Model instance related to this Instane
    public static func makeModel() throws -> Model {
        return try Model.makeModel(typeOf: Self.self)
    }
    
    /// Creates a Model instance related to this Instane
    public func makeModel() throws -> Model {
        return try Model.makeModel(typeOf: type(of: self).self)
    }
    
    /// Creates a Collection instance from this Model
    public static func makeCollection() throws -> MongoKitten.Collection {
        return try makeModel().collection
    }
    
    /// Counts the amount of Instances matching the query
    public static func count(matching query: Query? = nil) throws -> Int {
        return try makeCollection().count(matching: query)
    }
    
    /// Finds the first Instance matching the query
    ///
    /// Will return nil if none are found
    public static func findOne(matching query: Query? = nil) throws -> Self? {
        guard let document = try makeCollection().findOne(matching: query) else {
            return nil
        }
        
        return try Self.init(document, validatingDocument: true)
    }
    
    /// Finds all Instances matching the query
    ///
    /// Can be grouped in an Array using `Array(InstanceType.find(matching: ...))`
    ///
    /// Or can be looped over using for loops
    ///
    /// `for instance in InstanceType.find(matching: ...)`
    public static func find(matching query: Query? = nil) throws -> Cursor<Self> {
        return Cursor(base: try makeCollection().find(matching: query)) {
            try? Self.init($0, validatingDocument: true)
        }
    }
    
    /// Finds the firsts Partial Instance matching the query. The partial will only have all fields avaiable that are enabled in the Projection
    ///
    /// Will return nil if none are found
    public static func findOne(matching query: Query? = nil, projecting projection: Projection) throws -> Self? {
        guard let document = try makeCollection().findOne(matching: query, projecting: projection) else {
            return nil
        }
        
        return try Self.init(document, projectedBy: projection, validatingDocument: true)
    }
    
    /// Finds the firsts Partial Instance matching the query. The partial will only have all fields avaiable that are enabled in the Projection
    ///
    /// Can be grouped in an Array using `Array(InstanceType.find(matching: ...))`
    ///
    /// Or can be looped over using for loops
    ///
    /// `for instance in InstanceType.find(matching: ...)`
    public static func find(matching query: Query? = nil, projecting projection: Projection) throws -> Cursor<Self> {
        return Cursor(base: try makeCollection().find(matching: query, projecting: projection)) {
            try? Self.init($0, projectedBy: projection, validatingDocument: true)
        }
    }
}
