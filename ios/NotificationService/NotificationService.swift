import UserNotifications
import Intents

class NotificationService: UNNotificationServiceExtension {
    
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    
    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        guard let content = bestAttemptContent else {
            contentHandler(request.content)
            return
        }
        
        let data = request.content.userInfo
        let avatarUrlString = (data["avatarUrl"] as? String)
            ?? (data["fcm_options"] as? [String: Any])?["image"] as? String
        let senderName = content.title
        let senderId = (data["senderId"] as? String) ?? "unknown"
        
        guard let avatarUrlString = avatarUrlString,
              !avatarUrlString.isEmpty,
              let avatarUrl = URL(string: avatarUrlString) else {
            contentHandler(content)
            return
        }
        
        downloadImage(from: avatarUrl) { [weak self] imageData in
            guard let self = self else {
                contentHandler(content)
                return
            }
            
            guard let imageData = imageData else {
                contentHandler(content)
                return
            }
            
            let updatedContent = self.createCommunicationNotification(
                content: content,
                senderName: senderName,
                senderId: senderId,
                avatarData: imageData
            ) ?? content
            
            contentHandler(updatedContent)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let content = bestAttemptContent {
            contentHandler(content)
        }
    }
    
    private func createCommunicationNotification(
        content: UNMutableNotificationContent,
        senderName: String,
        senderId: String,
        avatarData: Data
    ) -> UNNotificationContent? {
        let handle = INPersonHandle(value: senderId, type: .unknown)
        
        var personImage: INImage? = nil
        personImage = INImage(imageData: avatarData)
        
        let sender = INPerson(
            personHandle: handle,
            nameComponents: {
                var name = PersonNameComponents()
                name.nickname = senderName
                return name
            }(),
            displayName: senderName,
            image: personImage,
            contactIdentifier: nil,
            customIdentifier: senderId
        )
        
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: senderId,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        
        intent.setImage(personImage, forParameterNamed: \.sender)
        
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)
        
        do {
            let updatedContent = try content.updating(from: intent)
            return updatedContent
        } catch {
            print("NotificationService: Failed to update content: \(error)")
            return nil
        }
    }
    
    private func downloadImage(from url: URL, completion: @escaping (Data?) -> Void) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                completion(nil)
                return
            }
            completion(data)
        }
        task.resume()
    }
}
