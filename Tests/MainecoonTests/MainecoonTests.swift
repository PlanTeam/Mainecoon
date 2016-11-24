import XCTest
@testable import Mainecoon

class MainecoonTests: XCTestCase {
    func testEmbeddedDocuments() throws {
        let realGroup = try Group.make(fromDocument: ["name": "bob"]) as Group
        
        try realGroup.store()
        try db.server.fsync(async: false, blocking: true)
        
        let realUser = try User.make(fromDocument: ["username": "Bert", "group": realGroup.makeReference().bsonValue, "age": 123]) as User
        
        try realUser.setEmbeddedInstance(toReferenceOf: realGroup, withProjection: ["name"], forKey: "embeddedgroup")
        
        try realUser.store()
        
        guard let reference = realUser.getEmbeddedInstance(forKey: "embeddedgroup") else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(reference.embeddedDocument["name"] as? String, "bob")
        
        guard let groupReference = try reference.resolveReference() as? Group else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(groupReference.name, "bob")
    }
    
    func testEntityProjections() throws {
        let realGroup = try Group.make(fromDocument: ["name": "bob"]) as Group
        
        try realGroup.store()
        try db.server.fsync(async: false, blocking: true)
        
        let realUser = try User.make(fromDocument: ["username": "Bert", "group": realGroup.makeReference().bsonValue, "age": 123]) as User
        
        try realUser.store()
        try db.server.fsync(async: false, blocking: true)
        
        let user = try User(fromIdentifier: realUser.identifier.makeBsonValue(), projectedBy: ["username", "group"])
        
        XCTAssertNil(user.getProperty(forKey: "age") as String?)
        XCTAssertEqual(user.username, "Bert")
        
        user.setProperty(toValue: "Henk", forKey: "username")
        
        try user.store()
        try db.server.fsync(async: false, blocking: true)
        
        let user2 = try User(fromIdentifier: realUser.identifier.makeBsonValue())
        
        XCTAssertEqual(user2.username, "Henk")
        XCTAssertEqual(user2.getProperty(forKey: "age") as Int?, 123)
    }
    
    override func setUp() {
        _ = groupModel
        _ = userModel
    }
    
    func testEntityRelations() throws {
        XCTAssertNil(try? Group.make(fromDocument: ["bob": true]) as Group)
        
        let realGroup = try Group.make(fromDocument: ["name": "bob"]) as Group
        
        try realGroup.store()
        try db.server.fsync(async: false, blocking: true)
        
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

let groupModel = try! registerModel(named: ("group", "groups"), withSchematics: [
    "name": (.string, true)
    ], inDatabase: db, instanceType: Group.self)

let userModel = try! registerModel(named: ("user", "users"), withSchematics: [
    "username": (.nonEmptyString, true),
    "age": (.number, false),
    "group": (.reference(model: Group.self), true)
    ], inDatabase: db, instanceType: User.self)

class Group: BasicInstance {
    var name: String {
        get {
            return self.getProperty(forKey: "name").string
        }
        set {
            self.setProperty(toValue: newValue, forKey: "name")
        }
    }
}

class User: BasicInstance {
    var username: String {
        get {
            return self.getProperty(forKey: "username").string
        }
        set {
            self.setProperty(toValue: newValue, forKey: "username")
        }
    }
    
    var group: Group? {
        get {
            do {
                return try self.getReference(forKey: "group") as? Group
            } catch {
                return nil
            }
        }
        set {
            guard let newValue = newValue else {
                return
            }
            
            self.setReference(toReferenceOf: newValue, forKey: "group")
        }
    }
}
