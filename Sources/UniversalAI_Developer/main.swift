import Foundation
import OpenAI
import Dispatch

func getUserAPIKey() -> String {
    let keyPath = "user_key.txt"

    if let key = try? String(contentsOfFile: keyPath, encoding: .utf8) {
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        print("Please enter your OpenAI API key:")
        let key = readLine()!.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try key.write(toFile: keyPath, atomically: true, encoding: .utf8)
            print("API key saved to file.")
        } catch {
            print("Error saving API key to file. Please try again.")
        }

        return key
    }
}

class UserAssistantDialogue {
    private let modelName: String
    private var messages: [OpenAI.Chat]
    private let initialPrompt: String
    private let openAI: OpenAI

    init(apiToken: String, modelName: String) {
        self.modelName = modelName
        self.messages = []
        self.initialPrompt = """
        {
          "type": "ai_instructions",
          "content": "You are an AI coder assistant integrated into UAD. Your task is to help with continuous code development and existing code base editing based on user input in natural human language. When responding, your response should only consist of a JSON object that follows this format:

            {
              \\"type\\": \\"ai_response\\",
              \\"actions\\": [
                {
                  \\"file_path\\": \\"file_path\\",
                  \\"action\\": \\"action\\",
                  \\"code\\": \\"code\\"
                }
              ]
            }

        For each action, use the corresponding keywords:
        - To create a file or folder, use \\"CREATE\\"
        - To edit a file, use \\"EDIT\\"
        - To delete a file, use \\"DELETE\\"

        Remember to strictly follow the format and avoid including any other words or symbols in your response !!!. Each action object in the 'actions' array will be interpreted as a new file action. Always provide concise and accurate code solutions based on user requests."
        }
        """

        self.openAI = OpenAI(apiToken: apiToken)
    }

    func generateResponse(for input: String, completion: @escaping (Result<String, Error>) -> Void) {
        let userInput = OpenAI.Chat(role: .user, content: input)

        let chatQuery = OpenAI.ChatQuery(
            model: modelName,
            messages: messages + [OpenAI.Chat(role: .system, content: initialPrompt), userInput]
        )

        openAI.chats(query: chatQuery) { result in
            DispatchQueue.global(qos: .userInitiated).async {
                switch result {
                case .success(let chatResult):
                    if let response = chatResult.choices.first?.message.content {
                        completion(.success(response))
                    } else {
                        completion(.failure(OpenAI.OpenAIError.emptyData))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}

func processCommands(response: String, currentProject: Project) {
    let jsonData = Data(response.utf8)
    do {
        if let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
           let actions = jsonObject["actions"] as? [[String: Any]] {
            for action in actions {
                if let file_path = action["file_path"] as? String,
                   let actionType = action["action"] as? String,
                   let code = action["code"] as? String {
                    let fullPath = currentProject.folderPath + file_path
                    switch actionType {
                    case "CREATE":
                        createFile(atPath: fullPath, withCode: code)
                    case "EDIT":
                        editFile(atPath: fullPath, withCode: code)
                    case "DELETE":
                        deleteFile(atPath: fullPath)
                    default:
                        print("Invalid action: \(actionType)")
                    }
                }
            }
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func parseGeneratedCode(response: String) -> [String: (String, String)] {
    var fileActions: [String: (String, String)] = [:]

    let jsonData = Data(response.utf8)
    do {
        if let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
           let actions = jsonObject["actions"] as? [[String: Any]] {
            for action in actions {
                if let file_path = action["file_path"] as? String,
                   let actionType = action["action"] as? String,
                   let code = action["code"] as? String {
                    fileActions[file_path] = (actionType, code)
                }
            }
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }

    return fileActions
}

func performFileActions(basePath: String, fileActions: [(file_path: String, action: String, code: String)], completion: @escaping () -> Void) {
    for fileAction in fileActions {
        let fullPath = basePath + fileAction.file_path

        switch fileAction.action {
        case "CREATE":
            createFile(atPath: fullPath, withCode: fileAction.code)
        case "EDIT":
            editFile(atPath: fullPath, withCode: fileAction.code)
        case "DELETE":
            deleteFile(atPath: fullPath)
        default:
            print("Invalid action: \(fileAction.action)")
        }
    }
    completion()
}

func createFile(atPath filePath: String, withCode code: String?) {
    let fileManager = FileManager.default

    if let directoryPath = filePath.split(separator: "/").dropLast().joined(separator: "/") as String? {
        if !fileManager.fileExists(atPath: directoryPath) {
            do {
                try fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true, attributes: nil)
                print("Created directory: \(directoryPath)")
            } catch {
                print("Error creating directory: \(directoryPath). Error: \(error)")
            }
        }
    }

    do {
        let content = code ?? ""
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
        print("Created file: \(filePath)")
    } catch {
        print("Error creating file: \(filePath). Error: \(error)")
    }
}

func editFile(atPath filePath: String, withCode code: String) {
    do {
        try code.write(toFile: filePath, atomically: true, encoding: .utf8)
        print("Edited file: \(filePath)")
    } catch {
        print("Error editing file: \(filePath). Error: \(error)")
    }
}

func deleteFile(atPath filePath: String) {
    do {
        try FileManager.default.removeItem(atPath: filePath)
        print("Deleted file: \(filePath)")
    } catch {
        print("Error deleting file: \(filePath). Error: \(error)")
    }
}

// Initialize OpenAI with your API key
let modelName = "gpt-3.5-turbo"
let apiKey = getUserAPIKey()
let openai = OpenAI(apiToken: apiKey)

let userAssistantDialogue = UserAssistantDialogue(apiToken: apiKey, modelName: modelName)
let chatManager = ChatManager(userAssistantDialogue: userAssistantDialogue)

func startConversation(apiToken: String) {
    print("Enter a chat name to create a new chat or open an existing one:")
    if let chatName = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) {
        let semaphore = DispatchSemaphore(value: 0)

        chatManager.createNewChat(name: chatName, completion: { (selectedProject) in
            guard let selectedProject = selectedProject else {
                print("Error: Project not selected or created.")
                semaphore.signal()
                return
            }
            chatManager.openChat(chatName: chatName)
            semaphore.signal()
        })

        semaphore.wait()
        proceedWithConversation(apiToken: apiToken)
        
    } else {
        print("Invalid chat name.")
        return
    }
}

func proceedWithConversation(apiToken: String) {
    let dialogue = UserAssistantDialogue(apiToken: apiToken, modelName: modelName)
    
    print("Let's write some real code! UAD is ready to receive your instructions.\nPlease review generated code, decompose your tasks as much a possible.")
    print("Type 'exit' to end the conversation.\n")
    
    guard let currentProject = chatManager.currentProject else {
        print("Error: No current project found.")
        return
    }

    while true {
        print("> ", terminator: "")
        if let userInput = readLine(), !userInput.isEmpty {
            if userInput.lowercased() == "exit" {
                break
            }

            let semaphore = DispatchSemaphore(value: 0)
            dialogue.generateResponse(for: userInput) { result in
                switch result {
                case .success(let response):
                    // Save user request and AI response to chat history
                    let chatHistory = chatManager.loadChatHistory(chatName: chatManager.currentChatName!)
                    let updatedHistory = chatHistory + "\nUser: \(userInput)\nGPT-4: \(response)"
                    chatManager.saveChatHistory(chatName: chatManager.currentChatName!, history: updatedHistory)
                    print("GPT-4: \(response)")

                    // Task confirmation
                    print("\nDo you approve script execution? (yes/no):")
                    let confirmation = readLine()?.lowercased()

                    if confirmation == "yes" {
                        print("Processing commands...")
                        processCommands(response: response, currentProject: currentProject)
                        print("Commands executed successfully.")
                    } else {
                        print("Instructions have been rejected by user. Update your ")
                    }
                case .failure(let error):
                    print("Error: \(error.localizedDescription)")
                }
                semaphore.signal()
            }
            semaphore.wait()
        } else {
            print("Please enter a valid input.")
        }
    }
}

startConversation(apiToken:apiKey)
