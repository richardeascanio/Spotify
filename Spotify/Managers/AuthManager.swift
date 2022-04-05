//
//  AuthManager.swift
//  Spotify
//
//  Created by Richard Ascanio on 4/4/22.
//

import Foundation

final class AuthManager {
    // We need only one instance of this class in the whole app (Singleton)
    static let shared = AuthManager()
    
    private var refreshingToken = false
    
    struct Constants {
        static let clientID = "332ac436843a49d0bc757cdb88c02478"
        static let clientSecret = "c7fd58cbdeea4605a09eacee6a0c4930"
        static let ACCOUNTS_BASE_URL = "https://accounts.spotify.com"
        static let tokenAPIUrl = "\(ACCOUNTS_BASE_URL)/api/token"
        static let redirectUri = "https://www.iosacademy.io"
        static let scopes = "user-read-private&20playlist-modify-public&20playlist-read-private&20playlist-modify-private&20user-follow-read&20user-library-modify&20user-library-read&20user-read-email"
    }
    
    // Privatize init so no one can create a new instance of this class
    private init() {}
    
    public var signInURL: URL? {
        let baseUrl = "\(Constants.ACCOUNTS_BASE_URL)/authorize"
        let string = "\(baseUrl)?response_type=code&client_id=\(Constants.clientID)&scope=\(Constants.scopes)&redirect_uri=\(Constants.redirectUri)&show_dialog=true"
        return URL(string: string)
    }
    
    var isSignedIn: Bool {
        return accessToken != nil
    }
    
    private var accessToken: String? {
        return UserDefaults.standard.string(forKey: "accessToken")
    }
    
    private var refreshToken: String? {
        return UserDefaults.standard.string(forKey: "refreshToken")
    }
    
    private var tokenExpirationDate: Date? {
        return UserDefaults.standard.object(forKey: "expirationDate") as? Date
    }
    
    private var shouldRefreshToken: Bool {
        guard let expirationDate = tokenExpirationDate else {
            return false
        }
        let currentDate = Date()
        let fiveMinutes: TimeInterval = 300
        return currentDate.addingTimeInterval(fiveMinutes) >= expirationDate
    }
    
    public func exchangeCodeForToken(code: String, completion: @escaping ((Bool) -> Void)) {
        // Get Token from code (Spotify method)
        guard let url = URL(string: Constants.tokenAPIUrl) else {
            return
        }
        
        // Body in the POST Request
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: Constants.redirectUri)
        ]
        
        // Create the Request
        var request = URLRequest(url: url)
        // Set request method
        request.httpMethod = "POST"
        // Set one request header (needed by Spotify API)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Set request body (Spotify needs it to be enconded utf8)
        request.httpBody = components.query?.data(using: .utf8)
        // Create token for other Spotify header
        let basicToken = "\(Constants.clientID):\(Constants.clientSecret)"
        let data = basicToken.data(using: .utf8)
        // Enconding token in base 64 (needed by Spotify API)
        guard let base64String = data?.base64EncodedString() else {
            print("Failure to get base64")
            completion(false)
            return
        }
        // Setting value to the request header
        request.setValue("Basic \(base64String)", forHTTPHeaderField: "Authorization")
        
        // Sending request to server
        // [weak self] because we are in a closure and it may cause a memory leak
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let safeData = data, error == nil else {
                // Handle error response
                completion(false)
                return
            }
            
            do {
                // Handle success response
                let result = try JSONDecoder().decode(AuthResponse.self, from: safeData)
                print("Access code for token")
                let jsonResult = try JSONSerialization.jsonObject(with: safeData, options: .allowFragments)
                print(jsonResult)
                self?.cacheToken(result: result)
                completion(true)
            } catch {
                // Error handling response data
                completion(false)
                print(error.localizedDescription)
            }
        }
        task.resume()
    }
    
    // Get Bearer token
    public func getBearerToken(completion: @escaping (Bool) -> Void) {
        // Get Token from code (Spotify method)
        guard let url = URL(string: Constants.tokenAPIUrl) else {
            return
        }
        
        // Body in the POST Request
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: Constants.clientID),
            URLQueryItem(name: "client_secret", value: Constants.clientSecret)
        ]
        
        // Create the Request
        var request = URLRequest(url: url)
        // Set request method
        request.httpMethod = "POST"
        // Set one request header (needed by Spotify API)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Set request body (Spotify needs it to be enconded utf8)
        request.httpBody = components.query?.data(using: .utf8)
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let safeData = data, error == nil else {
                // Handle error response
                completion(false)
                return
            }
            
            do {
                // Handle success response
                let result = try JSONDecoder().decode(AuthResponse.self, from: safeData)
                print("Get bearer token")
                let jsonResult = try JSONSerialization.jsonObject(with: safeData, options: .allowFragments)
                print(jsonResult)
                self?.cacheToken(result: result)
                completion(true)
            } catch {
                // Error handling response data
                completion(false)
                print(error.localizedDescription)
            }
        }
        task.resume()
    }
    
    private var onRefreshBlocks = [((String) -> Void)]()
    
    // Supplies valid token to be used with API Calls
    public func withValidToken(completion: @escaping (String) -> Void) {
        guard !refreshingToken else {
            // Append the completion
            onRefreshBlocks.append(completion)
            return
        }
        if shouldRefreshToken {
            // Refresh
            print("Have to refresh token")
            refreshAccessTokenIfNeeded { [weak self] success in
                if let token = self?.accessToken, success {
                    completion(token)
                }
            }
        } else if let token = accessToken {
            print("Using same token")
            completion(token)
        }
    }
    
    public func refreshAccessTokenIfNeeded(completion: @escaping (Bool) -> Void) {
        guard !refreshingToken else {
            return
        }
        
        guard shouldRefreshToken else {
            completion(true)
            return
        }
        guard let refreshToken = self.refreshToken else {
            return
        }

        // Refresh the token
        guard let url = URL(string: Constants.tokenAPIUrl) else {
            return
        }
        
        refreshingToken = true
        
        // Body in the POST Request
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        
        // Create the Request
        var request = URLRequest(url: url)
        // Set request method
        request.httpMethod = "POST"
        // Set one request header (needed by Spotify API)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Set request body (Spotify needs it to be enconded utf8)
        request.httpBody = components.query?.data(using: .utf8)
        // Create token for other Spotify header
        let basicToken = "\(Constants.clientID):\(Constants.clientSecret)"
        let data = basicToken.data(using: .utf8)
        // Enconding token in base 64 (needed by Spotify API)
        guard let base64String = data?.base64EncodedString() else {
            print("Failure to get base64")
            completion(false)
            return
        }
        // Setting value to the request header
        request.setValue("Basic \(base64String)", forHTTPHeaderField: "Authorization")
        
        // Sending request to server
        // [weak self] because we are in a closure and it may cause a memory leak
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            self?.refreshingToken = false
            guard let safeData = data, error == nil else {
                // Handle error response
                completion(false)
                return
            }
            
            do {
                // Handle success response
                let result = try JSONDecoder().decode(AuthResponse.self, from: safeData)
                self?.onRefreshBlocks.forEach { $0(result.accessToken) }
                self?.onRefreshBlocks.removeAll()
                print("Successfully refreshed")
                self?.cacheToken(result: result)
                completion(true)
            } catch {
                // Error handling response data
                completion(false)
                print(error.localizedDescription)
            }
        }
        task.resume()
    }
    
    private func cacheToken(result: AuthResponse) {
        print("token to be saved is: \(result.accessToken)")
        UserDefaults.standard.setValue(result.accessToken, forKey: "accessToken")
        if let refresh = result.refreshToken {
            UserDefaults.standard.setValue(refresh, forKey: "refreshToken")
        }
        UserDefaults.standard.setValue(Date().addingTimeInterval(TimeInterval(result.expiresIn)), forKey: "expirationDate")
    }
}
