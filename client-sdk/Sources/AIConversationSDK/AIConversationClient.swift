import Foundation
import Combine

// MARK: - Models

public struct ChatMessage: Codable, Identifiable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let metadata: [String: Any]?
    public let timestamp: Date
    
    public init(role: MessageRole, content: String, metadata: [String: Any]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.metadata = metadata
        self.timestamp = Date()
    }
    
    enum CodingKeys: String, CodingKey {
        case id, role, content, metadata, timestamp
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        metadata = try container.decodeIfPresent([String: Any].self, forKey: .metadata)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

public enum MessageRole: String, Codable, CaseIterable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

public struct ChatRequest: Codable {
    public let threadId: String?
    public let messages: [ChatMessage]
    public let toolsWanted: Bool?
    public let quality: Quality
    public let stream: Bool
    public let modelPreference: ModelPreference?
    public let preferLocal: Bool // Nuovo: preferisci GPT-OSS locale
    
    public init(
        threadId: String? = nil,
        messages: [ChatMessage],
        toolsWanted: Bool? = nil,
        quality: Quality = .auto,
        stream: Bool = true,
        modelPreference: ModelPreference? = nil,
        preferLocal: Bool = true // Default: preferisci GPT-OSS locale
    ) {
        self.threadId = threadId
        self.messages = messages
        self.toolsWanted = toolsWanted
        self.quality = quality
        self.stream = stream
        self.modelPreference = modelPreference
        self.preferLocal = preferLocal
    }
    
    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case messages
        case toolsWanted = "tools_wanted"
        case quality
        case stream
        case modelPreference = "model_preference"
        case preferLocal = "prefer_local"
    }
}

public enum Quality: String, Codable, CaseIterable {
    case auto = "auto"
    case max = "max"
    case costOptimized = "cost_optimized"
}

public enum ModelPreference: String, Codable, CaseIterable {
    case openai = "openai"
    case anthropic = "anthropic"
    case gptOss = "gpt-oss" // Nuovo: supporto per GPT-OSS
    case auto = "auto"
}

public struct ChatResponse: Codable {
    public let content: String
    public let model: String
    public let threadId: String?
    public let metadata: ResponseMetadata
    
    enum CodingKeys: String, CodingKey {
        case content, model
        case threadId = "thread_id"
        case metadata
    }
}

public struct ResponseMetadata: Codable {
    public let modelUsed: String
    public let provider: String // Nuovo: provider del modello
    public let quality: String
    public let contextRetrieved: Bool
    public let tokensEstimated: Int
    public let isLocalModel: Bool // Nuovo: è un modello locale?
    public let serverLocation: String // Nuovo: posizione del server
    
    enum CodingKeys: String, CodingKey {
        case modelUsed = "model_used"
        case provider
        case quality
        case contextRetrieved = "context_retrieved"
        case tokensEstimated = "tokens_estimated"
        case isLocalModel = "is_local_model"
        case serverLocation = "server_location"
    }
}

public struct RAGQuery: Codable {
    public let query: String
    public let limit: Int
    public let similarityThreshold: Double
    public let includeMetadata: Bool
    public let searchType: SearchType
    
    public init(
        query: String,
        limit: Int = 5,
        similarityThreshold: Double = 0.7,
        includeMetadata: Bool = true,
        searchType: SearchType = .hybrid
    ) {
        self.query = query
        self.limit = limit
        self.similarityThreshold = similarityThreshold
        self.includeMetadata = includeMetadata
        self.searchType = searchType
    }
    
    enum CodingKeys: String, CodingKey {
        case query, limit
        case similarityThreshold = "similarity_threshold"
        case includeMetadata = "include_metadata"
        case searchType = "search_type"
    }
}

public enum SearchType: String, Codable, CaseIterable {
    case hybrid = "hybrid"
    case vector = "vector"
    case text = "text"
}

public struct RAGResponse: Codable {
    public let query: String
    public let results: [RAGResult]
    public let metadata: RAGMetadata
}

public struct RAGResult: Codable, Identifiable {
    public let id: String
    public let content: String
    public let metadata: [String: Any]?
    public let score: Double
    
    enum CodingKeys: String, CodingKey {
        case id, content, metadata, score
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        metadata = try container.decodeIfPresent([String: Any].self, forKey: .metadata)
        score = try container.decode(Double.self, forKey: .score)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encode(score, forKey: .score)
    }
}

public struct RAGMetadata: Codable {
    public let totalResults: Int
    public let searchType: String
    public let similarityThreshold: Double
    public let queryLength: Int
    
    enum CodingKeys: String, CodingKey {
        case totalResults = "total_results"
        case searchType = "search_type"
        case similarityThreshold = "similarity_threshold"
        case queryLength = "query_length"
    }
}

// MARK: - Errors

public enum AIConversationError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case serverError(String)
    case unauthorized
    case rateLimitExceeded
    case invalidRequest(String)
    case localModelUnavailable(String) // Nuovo: modello locale non disponibile
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .unauthorized:
            return "Unauthorized access"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .localModelUnavailable(let model):
            return "Local model \(model) is not available"
        }
    }
}

// MARK: - Client

public class AIConversationClient: ObservableObject {
    private let baseURL: String
    private let apiKey: String
    private let session: URLSession
    
    @Published public var isConnected = false
    @Published public var lastError: AIConversationError?
    @Published public var localModelsAvailable: [String] = [] // Nuovo: modelli locali disponibili
    
    public init(baseURL: String, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }
    
    // MARK: - Chat
    
    public func sendChat(
        request: ChatRequest
    ) -> AnyPublisher<ChatResponse, AIConversationError> {
        guard let url = URL(string: "\(baseURL)/chat") else {
            return Fail(error: AIConversationError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            return Fail(error: AIConversationError.decodingError(error))
                .eraseToAnyPublisher()
        }
        
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIConversationError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    throw AIConversationError.unauthorized
                case 429:
                    throw AIConversationError.rateLimitExceeded
                case 400...499:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Bad request"
                    throw AIConversationError.invalidRequest(errorMessage)
                case 500...599:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Server error"
                    throw AIConversationError.serverError(errorMessage)
                default:
                    throw AIConversationError.invalidResponse
                }
            }
            .decode(type: ChatResponse.self, decoder: JSONDecoder())
            .mapError { error in
                if let aiError = error as? AIConversationError {
                    return aiError
                }
                return AIConversationError.decodingError(error)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Streaming Chat
    
    public func sendStreamingChat(
        request: ChatRequest
    ) -> AnyPublisher<ChatResponse, AIConversationError> {
        guard let url = URL(string: "\(baseURL)/chat") else {
            return Fail(error: AIConversationError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            return Fail(error: AIConversationError.decodingError(error))
                .eraseToAnyPublisher()
        }
        
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIConversationError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    throw AIConversationError.unauthorized
                case 429:
                    throw AIConversationError.rateLimitExceeded
                case 400...499:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Bad request"
                    throw AIConversationError.invalidRequest(errorMessage)
                case 500...599:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Server error"
                    throw AIConversationError.serverError(errorMessage)
                default:
                    throw AIConversationError.invalidResponse
                }
            }
            .decode(type: ChatResponse.self, decoder: JSONDecoder())
            .mapError { error in
                if let aiError = error as? AIConversationError {
                    return aiError
                }
                return AIConversationError.decodingError(error)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - RAG Query
    
    public func queryRAG(
        _ query: RAGQuery
    ) -> AnyPublisher<RAGResponse, AIConversationError> {
        guard let url = URL(string: "\(baseURL)/rag/query") else {
            return Fail(error: AIConversationError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(query)
        } catch {
            return Fail(error: AIConversationError.decodingError(error))
                .eraseToAnyPublisher()
        }
        
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIConversationError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    throw AIConversationError.unauthorized
                case 429:
                    throw AIConversationError.rateLimitExceeded
                case 400...499:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Bad request"
                    throw AIConversationError.invalidRequest(errorMessage)
                case 500...599:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Server error"
                    throw AIConversationError.serverError(errorMessage)
                default:
                    throw AIConversationError.invalidResponse
                }
            }
            .decode(type: RAGResponse.self, decoder: JSONDecoder())
            .mapError { error in
                if let aiError = error as? AIConversationError {
                    return aiError
                }
                return AIConversationError.decodingError(error)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Health Check
    
    public func checkHealth() -> AnyPublisher<Bool, AIConversationError> {
        guard let url = URL(string: "\(baseURL)/health") else {
            return Fail(error: AIConversationError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIConversationError.invalidResponse
                }
                
                return httpResponse.statusCode == 200
            }
            .mapError { error in
                if let aiError = error as? AIConversationError {
                    return aiError
                }
                return AIConversationError.networkError(error)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Local Models Check
    
    public func checkLocalModelsAvailability() -> AnyPublisher<[String], AIConversationError> {
        guard let url = URL(string: "\(baseURL)/health") else {
            return Fail(error: AIConversationError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIConversationError.invalidResponse
                }
                
                if httpResponse.statusCode == 200 {
                    // Parse response to check for local models
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let metadata = json["metadata"] as? [String: Any],
                       let localModels = metadata["local_models"] as? [String] {
                        return localModels
                    }
                }
                
                return []
            }
            .mapError { error in
                if let aiError = error as? AIConversationError {
                    return aiError
                }
                return AIConversationError.networkError(error)
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - Extensions

extension JSONEncoder {
    static let aiConversation: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}

extension JSONDecoder {
    static let aiConversation: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

// MARK: - Convenience Methods

public extension AIConversationClient {
    
    /// Convenience method to send a simple chat message with GPT-OSS preference
    func sendSimpleMessage(
        _ content: String,
        quality: Quality = .auto,
        preferLocal: Bool = true
    ) -> AnyPublisher<ChatResponse, AIConversationError> {
        let message = ChatMessage(role: .user, content: content)
        let request = ChatRequest(
            messages: [message],
            quality: quality,
            preferLocal: preferLocal
        )
        return sendChat(request: request)
    }
    
    /// Convenience method to send a message with specific model preference
    func sendMessageWithModel(
        _ content: String,
        model: ModelPreference,
        quality: Quality = .auto
    ) -> AnyPublisher<ChatResponse, AIConversationError> {
        let message = ChatMessage(role: .user, content: content)
        let request = ChatRequest(
            messages: [message],
            quality: quality,
            modelPreference: model,
            preferLocal: model == .gptOss // Prefer local only for GPT-OSS
        )
        return sendChat(request: request)
    }
} 