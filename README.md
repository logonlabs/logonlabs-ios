# LogonLabs iOS

The official LogonLabs iOS Client library.

## Download

### CocoaPods
Add these lines to your Podfile
```ruby
use_frameworks!
pod 'LogonLabs', '~> 1.0'
```

## LogonLabs API


- Prior to coding, some configuration is required at https://app.logonlabs.com/app/#/app-settings.

- For the full Developer Documentation please visit: https://app.logonlabs.com/api/

---
### Instantiating a new client

- Your `APP_ID` can be found in [App Settings](https://app.logonlabs.com/app/#/app-settings)
- The `LOGONLABS_API_ENDPOINT` should be set to `https://api.logonlabs.com`
- The `DESTINATION_URL` should be set to the custom url scheme for your application
  - Note: this url must be added to the Destination Url Whitelist for your App via [App Settings](https://app.logonlabs.com/app/#/app-settings)

Create a new instance of `LogonClient`.  

```swift
import LogonLabs;

let logonClient = LogonClient(baseUri: "{LOGONLABS_API_ENDPOINT}", appId: "{APP_ID}");
```
---
### SSO Login QuickStart

The StartLogin function in the iOS library begins the LogonLabs managed SSO process.

#### Step One

The following example demonstrates what to do once the `Callback Url` has been used by our system to redirect the user back to your page:

```swift
var body: some View {
    VStack {
        Button(action: {
            
            logonClient.startLogin(identity_provider: "google", destinationUrl: "") {error in
                if(error != nil) {
                    print(error.description!)
                }
            }
        }){
        Text("Start SSO Workflow")
        }
    }
}
```

#### Step Two

The user will be redirected to their iPhone browser and prompted to login with the specified identity provider.  At the end the user will be redirected to your backend server.  After calling ValidateLogin there will be a destination_url parameter that should be redirected back to with a query parameter called `payload`.  This can contain whatever required by your mobile application and should be Base64 encoded.

#### Step Three

```swift
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        
    var payload : String?
    logonClient.parsePayload(urlContexts: URLContexts) { result in
        switch result {
        case .failure(let e ):
            payload = e.description
        case .success(let p):
            payload = p
        }
    }
    
    //An example of passing the information to the view but
    let view = AuthenticatedView(data: payload)
    if let windowScene = scene as? UIWindowScene {
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: view)
        self.window = window
        window.makeKeyAndVisible()
    }
}

```

---
### Helper Methods
#### GetProviders
This method is used to retrieve a list of all providers enabled for the application.
If an email address is passed to the method, it will return the list of providers available for that email domain.
If any Enterprise Identity Providers have been configured a separate set of matching providers will also be returned in enterprise_identity_providers.

```swift
import LogonLabs;

logonClient.getProviders(emailAddress: "example@domain.com") {result in

    switch result {
    case .success(let providerData):
        if let suggestedProvider = providerData.suggestedProvider {
            print(suggestedProvider.rawValue) //google or microsoft
        }
        
        for socialProvider in providerData.socialIdentityProviders {
            print(socialProvider.type.rawValue) //google, microsoft, okta, etc
        }

        for enterpriseProvider in providerData.enterpriseIdentityProviders {
            print("Provider Name: \(enterpriseProvider.name)")
            print("Provider Id: \(enterpriseProvider.identityProviderId)")
            print("Provider Type: \(enterpriseProvider.type.rawValue)")
        }
    case .failure(let error):
        print(error.description!)
    }
}
```