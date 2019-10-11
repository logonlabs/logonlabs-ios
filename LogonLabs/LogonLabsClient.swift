//
//  LogonLabsClient.swift
//  SdkPoc
//
//  Created by Isiah Pasquale on 2019-09-23.
//  Copyright © 2019 Isiah Pasquale. All rights reserved.
//

import Foundation
import UIKit

public class LogonLabsClient : NSObject {
    
    private var baseUri : String
    private var appId : String
    
    public init(baseUri: String, appId: String) {
        self.baseUri = baseUri
        if !self.baseUri.hasSuffix("/") {
            self.baseUri = self.baseUri + "/"
        }
        self.appId = appId
    }
    
    /// Starts the SSO login process.  Opens Safari and redirects the user to the chosen identity provider.
    /// This is specified by either the name of the provider or by the ID of it.
    ///
    /// - Parameters:
    ///   - identityProvider: The name of the identity provider for the login.  If this has value then identityProviderId must be nil.
    ///   - identityProviderId: The unique identifier for the provider.  This is only used for Enterprise Providers.  If this has value then identityProvider must be nil.
    ///   - destinationUrl: The custom URL mapping to reopen the application.  Required by almost all mobile workflows.
    ///   - callbackUrl: The URL that LogonLabs will send the call back to.  Not required unless you need a different call back location from the default one configured.
    /// - Returns: LogonError in case of failure.  Otherwise calls RedirectLogin to open browser for SSO authentication.
    public func startLogin(identityProvider: ProviderTypes?, identityProviderId: String?, destinationUrl: String?, callbackUrl: String?, errorHandler: @escaping (LogonError?) -> Void) {
            
        if(identityProvider == nil && identityProviderId == nil) {
            errorHandler(LogonError(kind: .InvalidArgumentError, description: "identity_provider or identity_provider_id must have a value"))
        }
            
        if(identityProvider != nil && identityProviderId != nil) {
            errorHandler(LogonError(kind: .InvalidArgumentError, description: "identity_provider and identity_provider_id cannot both have a value"))
        }
        
        let identityProviderString = identityProvider?.rawValue
        
        guard let serviceUrl = URL(string: baseUri + "start") else {return}
        let identityProviderKey = identityProvider != nil ? "identity_provider" : "identity_provider_id"
        let identityProviderValue = identityProviderString ?? identityProviderId
        let parameterDictionary = ["app_id": appId, identityProviderKey: identityProviderValue, "destination_url": destinationUrl, "callback_url": callbackUrl]
        var request = URLRequest(url: serviceUrl)
        request.httpMethod = "POST"
        request.setValue("Application/json", forHTTPHeaderField: "Content-Type")
        guard let httpBody = try? JSONSerialization.data(withJSONObject: parameterDictionary, options: []) else {return}
        request.httpBody = httpBody
        
        let session = URLSession.shared
        session.dataTask(with: request) {(data, response, error) in
            if let data = data {
                do {
                    if let dictionary = try JSONSerialization.jsonObject(with: data, options: []) as? [String:Any] {
                        if let t = dictionary["token"] as? String {
                            self.redirectLogin(token: t)
                        } else if let e = dictionary["error"] as? [String:Any] {
                            errorHandler(self.parseError(kind: .StartLoginError, error: e))
                        }
                    }
                    
                } catch {
                    errorHandler(LogonError(kind: .DeserializationError))
                    
                }
            }
        }.resume()
    }
    
    /// Redirects the user to their chosen Identity Provider
    ///
    /// - Parameters:
    ///  - token: The login attempt's unique identifier returned by StartLogin
    /// - Returns: nil
    private func redirectLogin(token: String) {
        guard let url = URL(string: (baseUri + "redirect?token=" + token)) else { return }
        UIApplication.shared.open(url)
    }

    /// Gets a list of enabled providers
    ///
    /// - Parameters:
    ///  - emailAddress: Filters the list of providers by the email address' domain.
    /// - Returns: ProviderData object with lists of available providers on success.  LogonError on failure.
    public func getProviders(emailAddress: String?, responseHandler: @escaping (Result<ProviderData, LogonError>) -> Void) {
        
        var serviceUrl = URLComponents(string: baseUri + "providers")!
        var parameterDictionary = ["app_id": appId]
        if emailAddress != nil {
            parameterDictionary.updateValue(emailAddress!, forKey: "email_address")
        }
        
        serviceUrl.queryItems = parameterDictionary.map { (key, value) in
            URLQueryItem(name: key, value: value)
        }
        serviceUrl.percentEncodedQuery = serviceUrl.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: serviceUrl.url!)
        request.httpMethod = "GET"
        let session = URLSession.shared
        session.dataTask(with: request) {(data, response, error) in
            if let data = data {
                do {
                    if let dictionary = try JSONSerialization.jsonObject(with: data, options: []) as? [String:Any] {
                        //handle errors
                        if let e = dictionary["error"] as? [String:Any] {
                            responseHandler(.failure(self.parseError(kind: .GetProvidersError, error: e)))
                        } else {
                            
                            var providers = [Provider]()
                            var enterpriseProviders = [EnterpriseProvider]()
                            var recommendedProvider : ProviderTypes?
                            
                            //get social providers
                            if let idps = dictionary["social_identity_providers"] as? [[String:String]] {
                                for p in idps {
                                    if let providerType = ProviderTypes(rawValue: p["type"]!) {
                                        providers.append(Provider(type: providerType))
                                    }
                                }
                            }
                            
                            //get enterprise providers
                            if let eIdps = dictionary["enterprise_identity_providers"] as? [[String:String]] {

                                for eIdP in eIdps {
                                    enterpriseProviders.append(EnterpriseProvider(dictionary: eIdP))
                                }
                            }
                            
                            //get recommended provider
                            if let recommended = dictionary["suggested_identity_provider"] as? String {
                                recommendedProvider = ProviderTypes(rawValue: recommended)
                            }
                            
                            responseHandler(.success(ProviderData(socialProviders: providers, enterpriseProviders: enterpriseProviders, suggestedProvider: recommendedProvider)))
                        }
                        
                    }
                    
                } catch {
                    responseHandler(.failure(LogonError(kind: .DeserializationError)))
                }
            }
        }.resume()
    }
    
    private func parseError(kind: LogonError.ErrorKind, error: [String:Any]) -> LogonError {
        
        var errorCode : String?
        if let c = error["code"] as? String {
            errorCode = c
        }
        
        var errorMessage : String?
        if let m = error["message"] as? String {
            errorMessage = m
        }
        
        return LogonError(kind: kind, description: "errorCode: \(errorCode ?? "")\nerrorMessage: \(errorMessage ?? "")")
    }
    
    /// Helper method to parse out a Base 64 encoded payload.
    ///
    /// - Parameters:
    ///  - urlContexts: The URL context captured by the AppDelegate/SceneDelegate
    /// - Returns: The decoded payload as a String on success.  A LogonError on failure.
    public static func parsePayload(urlContexts: Set<UIOpenURLContext>, resultHandler: @escaping (Result<String, LogonError>) -> Void) {
        
        var payload : String?
        
        if let urlContext = urlContexts.first {
            let url = urlContext.url
            if let queryItems = NSURLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                for item in queryItems {
                    
                    if item.name == "payload" {
                        if let v = item.value {
                            if let decoded = Data(base64Encoded: v) {
                                payload = String(data: decoded, encoding: .utf8)
                            }
                            else {
                                resultHandler(.failure(LogonError(kind: .ParsePayloadError, description: "Payload must be in valid Base64 format.")))
                            }
                        }
                    }
                }
            }
        }
        
        if payload == nil {
            resultHandler(.failure(LogonError(kind: .ParsePayloadError, description: "No payload parameter found in query.")))
        } else{
            resultHandler(.success(payload!))
        }
    }
    
}

/// A structure containing provider details
public struct ProviderData {
    
    /// List of the Social Providers
    private(set) public var socialProviders : [Provider]
    
    /// List of the Enterprise Providers
    private(set) public var enterpriseProviders : [EnterpriseProvider]
    
    /// The suggested provider if an email address was provided to GetProviders
    private(set) public var suggestedProvider : ProviderTypes?
    
    /** Initializes a new ProviderData structure
            
        - Parameters:
            - socialProviders: List of Social Providers enabled
            - enterpriseProviders: List of Enterprise Providers enabled
            - suggestedProvider: Optional String that is the name of the recommended Provider based on the domain of the user
    */
    init(socialProviders: [Provider],
         enterpriseProviders: [EnterpriseProvider],
         suggestedProvider: ProviderTypes?)
    {
        self.socialProviders = socialProviders
        self.enterpriseProviders = enterpriseProviders
        self.suggestedProvider = suggestedProvider
    }
}

/// A structure containing the type of the Social Provider
public struct Provider {
    public let type : ProviderTypes
}

/// A structure containing the name, type and identifier for the Enterprise Provider
public struct EnterpriseProvider {
    
    /// The name of the Provider
    public let name : String
    
    /// The identifier of the Provider
    public let identityProviderId : String
    
    /// The type of the Provider
    public let type : ProviderTypes
    
    /** Initializes a new EnterpriseProvider structure
            
        - Parameter dictionary: Simple dictionary containing values for the three keys
    */
    init(dictionary: [String:String])
    {
        self.name = dictionary["name"]!
        self.identityProviderId = dictionary["identity_provider_id"]!
        self.type = ProviderTypes(rawValue: dictionary["type"]!)!
        
    }
}

/// All the valid types of Providers available in this version of LogonLabs
public enum ProviderTypes : String {
    case microsoft,
    google,
    facebook,
    linkedin,
    slack,
    twitter,
    github,
    okta,
    quickbooks,
    onelogin,
    apple,
    basecamp,
    dropbox,
    fitbit,
    planningcenter,
    twitch,
    amazon
}

/// The basic format of a LogonLabs Error
public struct LogonError : Error {

    /** Initializes a new LogonError
            
        - Parameter kind: The type of the error
        - Parameter description: The description of the error
    */
    public init(kind: ErrorKind, description: String)
    {
        self.kind = kind
        self.description = description
    }
    
    /** Initializes a new LogonError when description isn't important
            
        - Parameter kind: The type of the error
     */
    public init(kind: ErrorKind) {
        self.kind = kind
        self.description = nil
    }
    
    /// The type of the error
    public let kind: ErrorKind
    
    /// An optional description of the error
    public let description : String?
    
    /// Enum detailing the different possible error types
    public enum ErrorKind {
        case InvalidArgumentError
        case StartLoginError
        case GetProvidersError
        case DeserializationError
        case ParsePayloadError
    }
    
}
