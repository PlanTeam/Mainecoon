import BSON

public struct Schema: ValueConvertible, ExpressibleByDictionaryLiteral {
    public func makeBsonValue() -> Value {
        return BSONDocument(array: fields.map { $0.makeBsonValue() }).makeBsonValue()
    }
    
    let fields: [SchemaMetadata]
    var requirements: [(name: String, requirement: SchemaMetadata.FieldRequirement)] {
        return fields.map { field in
            switch field {
            case .optional(let name, let requirement): return (name, requirement)
            case .required(let name, let requirement): return (name, requirement)
            }
        }
    }
    
    public init(dictionaryLiteral elements: (String, (match: SchemaMetadata.FieldRequirement, required: Bool))...) {
        self.fields = elements.map { name, requirement in
            if requirement.required {
                return SchemaMetadata.required(named: name, matching: requirement.match)
            } else {
                return SchemaMetadata.optional(named: name, matching: requirement.match)
            }
        }
    }
    
    public func validate(_ document: BSONDocument, ignoringFields ignoredFields: Projection? = nil, allowExtraKeys: Bool = true) -> ValidationResult {
        fieldLoop: for field in fields {
            if let ignoredFields = ignoredFields, ignoredFields.document.keys.contains(field.name) {
                continue fieldLoop
            }
            
            let result = field.validate(against: document.makeBsonValue())
            
            guard case .valid = result else {
                return result
            }
        }
        
        return .valid
    }
    
    public enum ValidationResult: Error {
        case valid
        case invalid(reason: String)
    }
    
    public enum SchemaMetadata: ValueConvertible {
        public indirect enum FieldRequirement: ValueConvertible {
            case string, number, date, anyObject, bool, nonEmptyString, objectId
            case reference(model: Instance.Type)
            case object(matching: Schema)
            case enumeration([ValueConvertible])
            case array(of: FieldRequirement)
            case any(requirement: [FieldRequirement])
            case exactly(BSON.Value)
            case all(requirements: [FieldRequirement])
            case matchingRegex(String, withOptions: String)
            case anything
            
            public func validate(against value: Value, forKey key: String, allowExtraKeys: Bool = true) -> ValidationResult {
                switch (self, value) {
                case (.string, .string(_)):
                    return .valid
                case (.number, .double(_)):
                    return .valid
                case (.number, .int32(_)):
                    return .valid
                case (.number, .int64(_)):
                    return .valid
                case (.anyObject, .document(_)):
                    return .valid
                case (.objectId, .objectId):
                    return .valid
                case (.bool, .boolean):
                    return .valid
                case (.nonEmptyString, .string(let s)):
                    return s.characters.count > 0 ? .valid : .invalid(reason: "\(key) is of type String but is empty")
                case (.reference(let type), _):
                    do {
                        if case .document(let referenceDocument) = value {
                            guard let model = try? type.makeModel() else {
                                return .invalid(reason: "\(key) is a reference to an Instance of \(type). But the Instance does not have a registered Model")
                            }
                            
                            guard let reference = DBRef(referenceDocument, inDatabase: model.collection.database) else {
                                return .invalid(reason: "\(key) is a reference to an Instance of \(type). But the Document found at this key does not resolve to a usable DBRef.")
                            }
                            
                            let notFoundReason = "\(key) is a reference to an Instance of \(type). But it can't be resolved to a Document."
                            
                            do {
                                guard try reference.resolve() != nil else {
                                    return .invalid(reason: notFoundReason)
                                }
                                
                                return .valid
                            } catch {
                                return .invalid(reason: notFoundReason)
                            }
                        } else {
                            return try type.count(matching: "_id" == value) == 1 ? .valid : .invalid(reason: "\(key) is a reference to an Instance of \(type). But a matching model in this collection could not be found")
                        }
                    } catch {
                        return .invalid(reason: "Database lookup error")
                    }
                case (.object(let schema), .document(_)):
                    for match in schema.fields {
                        let result = match.validate(against: value, inScope: key)
                        
                        guard case .valid = result else {
                            return result
                        }
                    }
                    return .valid
                case (.enumeration(let array), _):
                    for arrayValue in array where arrayValue.makeBsonValue() == value {
                        return .valid
                    }
                    
                    return .invalid(reason: "\(key) does not match value in enumeration \(array)")
                case (.array(let elementRequirement), .array(let document)):
                    for element in document.arrayValue {
                        let result = elementRequirement.validate(against: element, forKey: key)
                        
                        guard case .valid = result else {
                            return result
                        }
                    }
                    
                    return .valid
                case (.any(let requirements), _):
                    for requirement in requirements {
                        if case .valid = requirement.validate(against: value, forKey: key) {
                            return .valid
                        }
                    }
                    
                    return .invalid(reason: "\(key) does not match any provided requirement")
                case (.exactly(let val), _):
                    return val == value ? .valid : .invalid(reason: "\(key) does not match \(val)")
                case (.all(let requirements), _):
                    for requirement in requirements {
                        let requirement = requirement.validate(against: value, forKey: key)
                        
                        guard case .valid = requirement else {
                            return requirement
                        }
                    }
                    
                    return .valid
                case (.anything, _):
                    return value != .nothing ? .valid : .invalid(reason: "\(key) doesn't exist")
                case (.matchingRegex(_, _), .string(_)):
                    fatalError("MKUnimplemented()")
                default:
                    return .invalid(reason: "\(key) does not match expeced type \(self.stringValue)")
                }
            }
            
            var stringValue: String {
                return "test"
            }
            
            public func makeBsonValue() -> Value {
                switch self {
                case .string:
                    return ["$type": "string"]
                case .number:
                    return ["$or": [
                        ["$type": "double"],
                        ["$type": "int"],
                        ["$type": "long"]
                        ]]
                case .date:
                    return ["$type": "date"]
                case .anyObject:
                    return ["$type": "object"]
                case .bool:
                    return ["$type": "bool"]
                case .nonEmptyString:
                    return ["$and": [
                        ["$type": "string"],
                        ["$ne": ""]
                        ]]
                case .reference(_), .objectId:
                    return ["$type": "objectId"]
                case .enumeration(let values):
                    return ["$in": BSON.Document(array: values.map { $0.makeBsonValue() }).makeBsonValue()]
                case .array(let requirement):
                    return ["$not": ["$elemMatch": ["$not": requirement.makeBsonValue()]]]
                case .any(let requirements):
                    return ["$or":
                        BSON.Document(array: requirements.map{$0.makeBsonValue()}).makeBsonValue()
                    ]
                case .exactly(let val):
                    return val
                case .all(let requirements):
                    return ["$and":
                        BSON.Document(array: requirements.map{$0.makeBsonValue()}).makeBsonValue()
                    ]
                case .matchingRegex(let pattern, let options):
                    return .regularExpression(pattern: pattern, options: options)
                case .anything:
                    return .nothing
                case .object(let schema):
                    return schema.makeBsonValue()
                }
            }
        }
        
        case optional(named: String, matching: FieldRequirement)
        case required(named: String, matching: FieldRequirement)
        
        var name: String {
            switch self {
            case .optional(let name, _): return name
            case .required(let name, _): return name
            }
        }
        
        public func validate(against value: Value, inScope scope: String? = nil, allowExtraKeys: Bool = true) -> ValidationResult {
            let scope = scope ?? ""
            
            switch self {
            case .optional(let name, let requirement):
                if case .nothing = value[name] {
                    return .valid
                }
                
                return requirement.validate(against: value[name], forKey: scope + name)
            case .required(let name, let requirement):
                return requirement.validate(against: value[name], forKey: scope + name)
            }
        }
        
        public func makeBsonValue() -> Value {
            switch self {
            case .optional(let name, let requirement):
                // TODO: FIX
                return ["$or": [
                    [name: requirement.makeBsonValue()], [name: ["$exists": false]]
                    ]]
            case .required(let name, let requirement):
                return [name: requirement.makeBsonValue()]
            }
        }
    }
}
