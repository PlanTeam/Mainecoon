import XCTest
@testable import Mainecoon

class MainecoonTests: XCTestCase {
    func testEntityProjections() throws {
        let realGroup = try Group.make(fromDocument: ["name": "bob"]) as Group
        let realUser = try User.make(fromDocument: ["username": "Bert", "group": realGroup.makeReference().bsonValue, "age": 123]) as User
        
        try realUser.store()
        
        guard let user = try User.findOne(matching: "_id" == realUser["_id"], projecting: ["username"]) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(user["age"], .nothing)
        XCTAssertEqual(user["username"], "Bert")
        
        user["username"] = "Henk"
        try user.store()
        
        guard let user2 = try User.findOne(matching: "_id" == realUser["_id"]) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(user2["username"], "Henk")
        XCTAssertEqual(user2["age"], 123)
    }
    
    override func setUp() {
        _ = groupModel
        _ = userModel
    }
    
    func testEntityRelations() throws {
        XCTAssertNil(try? Group.make(fromDocument: ["bob": true]) as Group)
        
        let realGroup = try Group.make(fromDocument: ["name": "bob"]) as Group
        
        XCTAssertNil(try? User.make(fromDocument: ["username": "Bert", "age": false, "group": ~ObjectId()]) as User)
        XCTAssertNil(try? User.make(fromDocument: ["username": "Bert", "age": false, "group": realGroup["_id"]]) as User)
        XCTAssertNil(try? User.make(fromDocument: ["username": "Bert", "group": ~ObjectId()]) as User)
        
        let realUser = try User.make(fromDocument: ["username": "Bert", "group": realGroup["_id"], "age": 123]) as User
        
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

let groupModel = registerModel(named: ("group", "groups"), withSchematics: [
    "name": (.string, true)
    ], inDatabase: db, instanceType: Group.self)

let userModel = registerModel(named: ("user", "users"), withSchematics: [
    "username": (.nonEmptyString, true),
    "age": (.number, false),
    "group": (.reference(model: Group.self), true)
    ], inDatabase: db, instanceType: User.self)

class Group: BasicInstance {
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
