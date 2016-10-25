import MongoKitten

extension Instance {
    public static func makeModel() throws -> Model {
        return try Model.makeModel(typeOf: Self.self)
    }
    
    public static func makeCollection() throws -> MongoKitten.Collection {
        return try makeModel().collection
    }
    
    public static func count(matching query: QueryProtocol) throws -> Int {
        return try makeCollection().count(matching: query)
    }
    
    public static func findOne(matching query: QueryProtocol) throws -> Instance? {
        let model = try makeModel()
        
        guard let document = try model.collection.findOne(matching: query) else {
            return nil
        }
        
        return try Self.init(document, asType: model, validatingDocument: true)
    }
    
    public static func find(matching query: QueryProtocol) throws -> Cursor<Instance> {
        let model = try makeModel()
        
        return Cursor(base: try model.collection.find(matching: query)) {
            try? Self.init($0, asType: model, validatingDocument: true)
        }
    }
    
    public static func findOne(matching query: QueryProtocol, projecting projection: Projection) throws -> Instance? {
        let model = try makeModel()
        
        guard let document = try model.collection.findOne(matching: query, projecting: projection) else {
            return nil
        }
        
        return try Self.init(document, asType: model, projectedBy: projection, validatingDocument: true)
    }
    
    public static func find(matching query: QueryProtocol, projecting projection: Projection) throws -> Cursor<Instance> {
        let model = try makeModel()
        
        return Cursor(base: try model.collection.find(matching: query, projecting: projection)) {
            try? Self.init($0, asType: model, projectedBy: projection, validatingDocument: true)
        }
    }
    
    public static func find<P: Instance>(matching query: QueryProtocol, projecting projection: Projection) throws -> Cursor<P> {
        let model = try Model.makeModel(typeOf: P.self)
        
        return Cursor(base: try model.collection.find(matching: query, projecting: projection)) {
            try? P.init($0, asType: model, projectedBy: projection, validatingDocument: true)
        }
    }
}
