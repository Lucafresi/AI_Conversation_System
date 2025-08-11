import SwiftUI
import Combine
import AIConversationSDK

// MARK: - AI Conversation View Model
class AIConversationViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let aiClient: AIConversationClient
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Inizializza il client con le tue configurazioni
        self.aiClient = AIConversationClient(
            baseURL: "https://your-edge-gateway.workers.dev", // Sostituisci con il tuo URL
            apiKey: "your-api-key-here" // Sostituisci con la tua API key
        )
    }
    
    // MARK: - Send Message
    func sendMessage(_ content: String) {
        let userMessage = ChatMessage(role: .user, content: content)
        messages.append(userMessage)
        
        isLoading = true
        errorMessage = nil
        
        let request = ChatRequest(
            messages: messages,
            toolsWanted: true, // Abilita RAG per contesto
            quality: .auto,
            stream: true
        )
        
        // Invia messaggio con streaming
        aiClient.sendStreamingChat(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    // Aggiorna l'ultimo messaggio o creane uno nuovo
                    if let lastMessage = self?.messages.last, lastMessage.role == .assistant {
                        // Aggiorna messaggio esistente
                        let updatedMessage = ChatMessage(
                            role: .assistant,
                            content: lastMessage.content + response.content
                        )
                        self?.messages[self?.messages.count ?? 1 - 1] = updatedMessage
                    } else {
                        // Crea nuovo messaggio
                        let assistantMessage = ChatMessage(
                            role: .assistant,
                            content: response.content
                        )
                        self?.messages.append(assistantMessage)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - RAG Query
    func queryKnowledgeBase(_ query: String) {
        let ragRequest = RAGQuery(
            query: query,
            limit: 5,
            searchType: .hybrid
        )
        
        aiClient.queryRAG(ragRequest)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    // Gestisci i risultati RAG
                    print("RAG Results: \(response.results.count) documents found")
                    for result in response.results {
                        print("- \(result.content) (Score: \(result.score))")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Clear Conversation
    func clearConversation() {
        messages.removeAll()
        errorMessage = nil
    }
}

// MARK: - AI Conversation View
struct AIConversationView: View {
    @StateObject private var viewModel = AIConversationViewModel()
    @State private var messageText = ""
    
    var body: some View {
        VStack {
            // Header
            HStack {
                Text("AI Assistant")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Clear") {
                    viewModel.clearConversation()
                }
                .foregroundColor(.blue)
            }
            .padding()
            
            // Messages
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                    }
                    
                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("AI is thinking...")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            
            // Error Message
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            
            // Input Area
            HStack {
                TextField("Type your message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Send") {
                    guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    viewModel.sendMessage(messageText)
                    messageText = ""
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                .foregroundColor(.blue)
            }
            .padding()
        }
        .onAppear {
            // Test connection
            viewModel.aiClient.checkHealth()
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { isHealthy in
                        if !isHealthy {
                            viewModel.errorMessage = "AI service is not available"
                        }
                    }
                )
                .store(in: &viewModel.cancellables)
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding()
                    .background(message.role == .user ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

// MARK: - Integration with Existing App
struct ExistingAppIntegration: View {
    @StateObject private var aiViewModel = AIConversationViewModel()
    
    var body: some View {
        TabView {
            // Your existing app content
            YourExistingContentView()
                .tabItem {
                    Image(systemName: "house")
                    Text("Home")
                }
            
            // AI Conversation
            AIConversationView()
                .tabItem {
                    Image(systemName: "message")
                    Text("AI Chat")
                }
        }
        .environmentObject(aiViewModel)
    }
}

// MARK: - Your Existing Content View (placeholder)
struct YourExistingContentView: View {
    var body: some View {
        VStack {
            Text("Your Existing App Content")
                .font(.title)
            
            Text("This is where your existing app content goes")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview
struct AIConversationView_Previews: PreviewProvider {
    static var previews: some View {
        AIConversationView()
    }
}

// MARK: - Usage Examples

/*
// Esempio di utilizzo nel tuo codice esistente:

class YourExistingViewModel: ObservableObject {
    private let aiClient = AIConversationClient(
        baseURL: "https://your-edge-gateway.workers.dev",
        apiKey: "your-api-key"
    )
    
    func askAIAboutWatch(_ question: String) {
        let request = ChatRequest(
            messages: [
                ChatMessage(role: .system, content: "You are an expert on Apple Watch and watchOS."),
                ChatMessage(role: .user, content: question)
            ],
            toolsWanted: true,
            quality: .max
        )
        
        aiClient.sendChat(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("AI Error: \(error)")
                    }
                },
                receiveValue: { response in
                    print("AI Response: \(response.content)")
                    print("Model used: \(response.metadata.modelUsed)")
                }
            )
            .store(in: &cancellables)
    }
}

// Esempio di integrazione con ConversationalView esistente:
extension ConversationalView {
    func integrateWithAISystem() {
        // Sostituisci la logica esistente con il nuovo sistema
        let aiClient = AIConversationClient(
            baseURL: "https://your-edge-gateway.workers.dev",
            apiKey: "your-api-key"
        )
        
        // Usa il client per le conversazioni AI
        // Il resto della tua UI rimane invariato
    }
}
*/ 