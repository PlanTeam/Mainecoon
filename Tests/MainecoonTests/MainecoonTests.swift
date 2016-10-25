import XCTest
@testable import Mainecoon

class MainecoonTests: XCTestCase {
    func testEntityProjections() throws {
        let realGroup = try Group(["name": "bob"])
        let realUser = try User(["username": "Bert", "group": realGroup.makeReference().bsonValue, "age": 123])
        
        try realUser.store()
        
        guard var user = try User.findOne(matching: "_id" == realUser["_id"], projecting: ["username"]) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(user["age"], .nothing)
        XCTAssertEqual(user["username"], "Bert")
        
        user["username"] = "Henk"
        try user.store()
        
        guard var user2 = try User.findOne(matching: "_id" == realUser["_id"]) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(user2["username"], "Henk")
        XCTAssertEqual(user2["age"], 123)
    }
    
    func testEntityRelations() throws {
        XCTAssertNil(try? Group(["bob": true]))
        
        let realGroup = try Group(["name": "bob"])
        
        XCTAssertNil(try? User(["username": "Bert", "age": false, "group": ~ObjectId()]))
        XCTAssertNil(try? User(["username": "Bert", "age": false, "group": realGroup["_id"]]))
        XCTAssertNil(try? User(["username": "Bert", "group": ~ObjectId()]))
        
        let realUser = try User(["username": "Bert", "group": realGroup["_id"], "age": 123])
        
        guard let group = realUser[reference: "group"] else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(group["name"], "bob")
    }
    
    static var allTests : [(String, (MainecoonTests) -> () throws -> Void)] {
        return [
            ("testEntityRelations", testEntityRelations),
            ("testEntityProjections", testEntityProjections),
        ]
    }
}

let db = try! Server(hostname: "localhost")["mainecoontest"]

let groupType = registerModel(named: ("group", "groups"), withSchematics: [
    "name": (.string, true)
    ], inDatabase: db)

let userType = registerModel(named: ("user", "users"), withSchematics: [
    "username": (.nonEmptyString, true),
    "age": (.number, false),
    "group": (.reference(model: Group.self), true)
    ], inDatabase: db)

class Group: BasicInstance {
    public init(_ document: Document) throws {
        try super.init(document, asType: groupType)
    }
    
    required init(_ document: Document, asType type: Model, validatingDocument validate: Bool) throws {
        try super.init(document, asType: type, validatingDocument: validate)
    }
    
    required init(_ document: Document, asType type: Model, projectedBy projection: Projection, validatingDocument validate: Bool) throws {
        try super.init(document, asType: type, projectedBy: projection, validatingDocument: validate)
    }
    
    var name: String {
        get {
            return self["name"].string
        }
        set {
            self["name"] = ~newValue
        }
    }
}

class User: BasicInstance {
    public init(_ document: Document) throws {
        try super.init(document, asType: userType)
    }
    
    required init(_ document: Document, asType type: Model, validatingDocument validate: Bool) throws {
        try super.init(document, asType: type, validatingDocument: validate)
    }
    
    required init(_ document: Document, asType type: Model, projectedBy projection: Projection, validatingDocument validate: Bool) throws {
        try super.init(document, asType: type, projectedBy: projection, validatingDocument: validate)
    }
    
    var username: String {
        get {
            return self["username"].string
        }
        set {
            self["username"] = ~newValue
        }
    }
    
    var group: Group? {
        get {
            return self[reference: "group"] as? Group
        }
        set {
            self[reference: "group"] = newValue
        }
    }
}
