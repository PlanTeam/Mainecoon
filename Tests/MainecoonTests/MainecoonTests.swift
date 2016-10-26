import XCTest
@testable import Mainecoon

class MainecoonTests: XCTestCase {
    func testEntityProjections() throws {
        let realGroup = try Group.make(fromDocument: ["name": "bob"]) as Group
        let realUser = try User.make(fromDocument: ["username": "Bert", "group": realGroup.makeReference().bsonValue, "age": 123]) as User
        
        try realUser.store()
        
        guard let user = try User.findOne(matching: "_id" == realUser.identifier, projecting: ["username"]) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(user.getProperty("age"), .nothing)
        XCTAssertEqual(user.username, "Bert")
        
        user.setProperty("username", toValue: "Henk")
        try user.store()
        
        guard let user2 = try User.findOne(matching: "_id" == realUser.identifier) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(user2.username, "Henk")
        XCTAssertEqual(user2.getProperty("age"), 123)
    }
    
    override func setUp() {
        _ = groupModel
        _ = userModel
    }
    
    func testEntityRelations() throws {
        XCTAssertNil(try? Group.make(fromDocument: ["bob": true]) as Group)
        
        let realGroup = try Group.make(fromDocument: ["name": "bob"]) as Group
        
        XCTAssertNil(try? User.make(fromDocument: ["username": "Bert", "age": false, "group": ~ObjectId()]) as User)
        XCTAssertNil(try? User.make(fromDocument: ["username": "Bert", "age": false, "group": realGroup.identifier]) as User)
        XCTAssertNil(try? User.make(fromDocument: ["username": "Bert", "group": ~ObjectId()]) as User)
        
        let realUser = try User.make(fromDocument: ["username": "Bert", "group": realGroup.identifier, "age": 123]) as User
        
        guard let group = realUser.group else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(group.name, "bob")
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
            return self.getProperty("name").string
        }
        set {
            self.setProperty("name", toValue: ~newValue)
        }
    }
}

class User: BasicInstance {
    var username: String {
        get {
            return self.getProperty("username").string
        }
        set {
            self.setProperty("username", toValue: ~newValue)
        }
    }
    
    var group: Group? {
        get {
            do {
                return try self.getReference("group") as? Group
            } catch {
                return nil
            }
        }
        set {
            guard let newValue = newValue else {
                return
            }
            
            self.setProperty("group", toReferenceOf: newValue)
        }
    }
}
