import Foundation

struct Project {
    let name: String
    let language: String
    let folderPath: String

    init(name: String, language: String) {
        self.name = name
        self.language = language
        self.folderPath = "Projects/\(name)/"
    }
}

struct Chat {
    let id: UUID
    let project: Project
}

class ChatManager {
    let chatDirectory = "Chats"
    var currentChatID: String?
    var currentChatName: String?
    private var chatMetadata: [String: Chat] = [:]
    var currentProject: Project?
    
    var existingProjects: [Project] = [] // Add a property to store existing projects
    
    let userAssistantDialogue: UserAssistantDialogue

    init(userAssistantDialogue: UserAssistantDialogue) {
        self.userAssistantDialogue = userAssistantDialogue
        createChatDirectoryIfNeeded()
        loadExistingProjects() // Load existing projects on initialization
    }
    
    func createChatDirectoryIfNeeded() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: chatDirectory) {
            do {
                try fileManager.createDirectory(atPath: chatDirectory, withIntermediateDirectories: false, attributes: nil)
            } catch {
                print("Error creating chat directory: \(error.localizedDescription)")
            }
        }
    }

    func loadExistingProjects() {
        let fileManager = FileManager.default
        let projectsDirectory = "./Projects" // Set the projects directory path here
        
        do {
            let directoryContents = try fileManager.contentsOfDirectory(atPath: projectsDirectory)
            let projectFolders = directoryContents.filter { folder in
                var isDirectory: ObjCBool = false
                let folderPath = projectsDirectory + "/\(folder)"
                fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }
            
            var loadedProjects: [Project] = []
            for folder in projectFolders {
                let folderPath = projectsDirectory + "/\(folder)"
                let languageFilePath = folderPath + "/language.txt"
                
                if fileManager.fileExists(atPath: languageFilePath) {
                    let language = try String(contentsOfFile: languageFilePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                    let project = Project(name: folder, language: language)
                    loadedProjects.append(project)
                }
            }
            existingProjects = loadedProjects
        } catch {
            print("Error loading existing projects: \(error.localizedDescription)")
        }
    }

    func selectExistingProject(_ existingProjects: [Project], completion: @escaping (Project) -> Void) -> Project? {
        print("Select an existing project:")
        for (index, project) in existingProjects.enumerated() {
            print("\(index + 1). \(project.name) (\(project.language))")
        }

        if let input = readLine(),
           let index = Int(input),
           index > 0 && index <= existingProjects.count {
            let selectedProject = existingProjects[index - 1]
            completion(selectedProject)
            return selectedProject
        } else {
            print("Invalid selection, please try again.")
            return nil
        }
    }

    func createNewProject(completion: @escaping (Project, Bool) -> Void) -> Project? {
        print("Enter a project name:")
        let projectName = readLine() ?? ""

        print("Enter the programming language:")
        let projectLanguage = readLine() ?? ""
        
        print("Enter the briefest possible project description:")
        let projectBrief = readLine() ?? ""

        let newProject = Project(name: projectName, language: projectLanguage)

        // Request the initial folder structure and template files from OpenAI API
        let prompt = """
        {
          "type": "ai_instructions",
          "content": "You are an AI coder assistant integrated into UAD. Your task is to generate a file and folder structure for a new project called \"\(projectName)\" using the \"\(projectLanguage)\" programming language, with the following logic: \"\(projectBrief)\". For each action, use the corresponding keywords: - To create a file or folder, use \\"CREATE\\" - To edit a file, use \\"EDIT\\" - To delete a file, use \\"DELETE\\". Each action object in the 'actions' array will be interpreted as a new file action. When responding, your response SHOULD SOLELY CONSIST (!!!) of a JSON object that follows this format:
            {
              \\"type\\": \\"ai_response\\",
              \\"actions\\": [
                {
                  \\"file_path\\": \\"file_path\\",
                  \\"action\\": \\"action\\",
                  \\"code\\": \\"code\\"
                }
              ]
            }"
        }
        """
        requestFolderStructureAndTemplates(prompt: prompt) { openAIResponse in
            // Display the response to the user
            print("OpenAI API response:\n\(openAIResponse)")

            // Ask the user for approval and create files with the provided code
            print("Do you approve the execution of these commands? (yes/no)")
            let userApproval = readLine() ?? "no"

            if userApproval.lowercased() == "yes" {
                processCommands(response: openAIResponse, currentProject: newProject)
                completion(newProject, true)
            } else {
                print("Project creation was not approved.")
                completion(newProject, false)
            }
        }
        return newProject
    }
    
    func openExistingProject(projectName: String, completion: @escaping () -> Void) {
        let projectPath = "Projects/\(projectName)"
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: projectPath) {
            print("Opened project: \(projectName)")
            print("Project path: \(projectPath)")

            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: projectPath), includingPropertiesForKeys: nil, options: [])
                print("Project files:")

                for fileURL in fileURLs {
                    print(fileURL.path)
                }
                completion()
            } catch {
                print("Error listing project files: \(error.localizedDescription)")
            }
        } else {
            print("Project not found.")
        }
    }
    
    func deleteProject(_ project: Project?) {
        guard let project = project else {
            print("Invalid project.")
            return
        }
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(atPath: project.folderPath)
            print("Deleted project: \(project.name)")
        } catch {
            print("Error deleting project: \(error.localizedDescription)")
        }
    }

    func renameProject(_ project: Project?, to newName: String) {
        guard let project = project else {
            print("Invalid project.")
            return
        }
        let newFolderPath = "Projects/\(newName)"
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: newFolderPath) {
            do {
                try fileManager.moveItem(atPath: project.folderPath, toPath: newFolderPath)
                print("Renamed project from \"\(project.name)\" to \"\(newName)\"")
            } catch {
                print("Error renaming project: \(error.localizedDescription)")
            }
        } else {
            print("A project with the new name already exists.")
        }
    }
    
    func createNewChat(name: String, completion: @escaping (Project?) -> Void) {
        let chatID = UUID().uuidString
        
        handleUserAction(completion: { (selectedProject) in
            guard let selectedProject = selectedProject else {
                print("Error: Project not selected or created.")
                completion(nil)
                return
            }
            let chat = Chat(id: UUID(uuidString: chatID)!, project: selectedProject)
            
            self.chatMetadata[chatID] = chat
            self.currentChatID = chatID
            let chatPath = self.chatDirectory + "/\(name)"

            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: chatPath) {
                do {
                    try fileManager.createDirectory(atPath: chatPath, withIntermediateDirectories: false, attributes: nil)
                    print("Created chat: \(name)")
                } catch {
                    print("Error creating chat directory: \(error.localizedDescription)")
                }
            } else {
                print("Chat with this name already exists")
            }

            // Create chat history file
            let historyFilePath = chatPath + "/history.txt"
            if !fileManager.fileExists(atPath: historyFilePath) {
                fileManager.createFile(atPath: historyFilePath, contents: nil, attributes: nil)
            }

            completion(selectedProject)
        })
    
    }

    func handleUserAction(completion: @escaping (Project?) -> Void) {
        var localProject: Project?
        print("Choose an action: (1) Select existing project, (2) Create new project, (3) Delete project, (4) Rename project, (5) List chats, (6) Delete chat, (7) Quit)")

        if let choice = readLine() {
            switch choice {
            case "1":
                print("Select an existing project:")
                if let selectedProject = selectExistingProject(existingProjects, completion: { _ in }) {
                    localProject = selectedProject
                    completion(localProject)
                } else {
                    print("No project selected.")
                }
            case "2":
                let newProject = createNewProject() { (project, commandsExecuted) in
                    if commandsExecuted {
                        completion(project)
                    } else {
                        print("Project creation was not approved. No chat will be opened.")
                        completion(nil)
                    }
                }
            case "3":
                print("Select a project to delete:")
                let projectToDelete = selectExistingProject(existingProjects, completion: { _ in })
                deleteProject(projectToDelete)
                // Reload the list of existing projects after deletion
                loadExistingProjects()
            case "4":
                print("Select a project to rename:")
                let projectToRename = selectExistingProject(existingProjects, completion: { _ in })
                print("Enter the new name for the project:")
                if let newName = readLine(), !newName.isEmpty {
                    renameProject(projectToRename, to: newName)
                    // Reload the list of existing projects after renaming
                    loadExistingProjects()
                } else {
                    print("Invalid project name.")
                }
            case "5":
                listChats()
                handleUserAction(completion: completion)
            case "6":
                print("Enter the name of the chat you want to delete:")
                if let chatName = readLine(), !chatName.isEmpty {
                    deleteChat(chatName: chatName)
                    handleUserAction(completion: completion)
                } else {
                    print("Invalid chat name.")
                    handleUserAction(completion: completion)
                }
            case "7":
                print("Exiting...")
            default:
                print("Invalid choice, please try again.")
                handleUserAction(completion: completion)
            }
        } else {
            print("Invalid choice, please try again.")
            handleUserAction(completion: completion)
        }
        completion(localProject)
    }

    func requestUserAction(completion: @escaping (Project?) -> Void) {
        print("Choose an action: (1) Select existing project, (2) Create new project, (3) Delete project, (4) Rename project, (5) List chats, (6) Delete chat, (7) Quit)")

        handleUserAction(completion: { (selectedProject) in
            completion(selectedProject)
        })
    }

    func listChats() {
        let fileManager = FileManager.default
        do {
            let directoryContents = try fileManager.contentsOfDirectory(atPath: chatDirectory)
            let chatFolders = directoryContents.filter { folder in
                var isDirectory: ObjCBool = false
                let folderPath = chatDirectory + "/\(folder)"
                fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }
            
            print("Available chats:")
            for folder in chatFolders {
                print("- \(folder)")
            }
        } catch {
            print("Error listing chats: \(error.localizedDescription)")
        }
    }

    func deleteChat(chatName: String) {
        let chatFolderPath = "Chats/\(chatName)"
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: chatFolderPath) {
            do {
                try fileManager.removeItem(atPath: chatFolderPath)
                print("Deleted chat: \(chatName)")
            } catch {
                print("Error deleting chat: \(error.localizedDescription)")
            }
        } else {
            print("Chat not found.")
        }
    }

    func encode(_ string: String) -> Data? {
        return string.data(using: .utf8)
    }
    
    func decode(_ data: Data) -> String? {
        return String(data: data, encoding: .utf8)
    }
    
    func chatPath(chatName: String) -> String {
        return "\(chatDirectory)/\(chatName)/history.txt"
    }
    
    func loadChatHistory(chatName: String) -> String {
        let path = chatPath(chatName: chatName)
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if let decodedData = decode(data) {
                return decodedData
            }
        } catch {
            print("Error loading chat history: \(error.localizedDescription)")
        }
        return ""
    }
    
    func saveChatHistory(chatName: String, history: String) {
        let path = chatPath(chatName: chatName)
        if let data = encode(history) {
            do {
                try data.write(to: URL(fileURLWithPath: path))
            } catch {
                print("Error saving chat history: \(error.localizedDescription)")
            }
        }
    }
    
    func clearChat(chatName: String) {
        saveChatHistory(chatName: chatName, history: "")
        print("Cleared chat: \(chatName)")
    }
    
    func getChatPath(chatName: String) -> String? {
        let chatFolderPath = "Chats/\(chatName)"
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: chatFolderPath) {
            return chatFolderPath
        }
        return nil
    }
    
    func openChat(chatName: String) {
        guard let chatPath = getChatPath(chatName: chatName) else {
            print("Error: Chat not found.")
            return
        }

        currentChatName = chatName
        currentProject = Project(name: chatName, language: "Swift") // Updated this line
        print("Chat opened: \(chatName)")
        let history = loadChatHistory(chatName: chatName)
        print("Chat history:\n\(history)")
    }
    
    func requestFolderStructureAndTemplates(prompt: String, completion: @escaping (String) -> Void) {
        userAssistantDialogue.generateResponse(for: prompt) { result in
            switch result {
            case .success(let response):
                completion(response)
            case .failure(let error):
                print("Error requesting folder structure and templates: \(error.localizedDescription)")
                completion("")
            }
        }
    }
}
