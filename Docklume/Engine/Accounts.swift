import Foundation

/// The account behind an OAuth token, asked from the service itself; rclone has no such query for these backends.
enum AccountLookup {
    static func email(type: String, token: String) async -> String? {
        guard let data = token.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { return nil }
        var request: URLRequest
        switch type {
        case "dropbox":
            request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/users/get_current_account")!)
            request.httpMethod = "POST"
        case "drive":
            request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)")!)
        case "onedrive":
            request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/drive?$select=owner")!)
        case "box":
            request = URLRequest(url: URL(string: "https://api.box.com/2.0/users/me?fields=login")!)
        default:
            return nil
        }
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        guard let (body, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        switch type {
        case "dropbox":
            return object["email"] as? String
        case "drive":
            return (object["user"] as? [String: Any])?["emailAddress"] as? String
        case "onedrive":
            let user = (object["owner"] as? [String: Any])?["user"] as? [String: Any]
            return user?["email"] as? String ?? user?["displayName"] as? String
        default:
            return object["login"] as? String
        }
    }
}
