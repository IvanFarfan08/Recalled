import SwiftUI
import RealityKit
import ARKit
import GoogleGenerativeAI
import Foundation
import FirebaseDatabase

//Config utilities: Read plist.
class ConfigManager {
    static func loadAPIKey() -> String? {
        guard let url = Bundle.main.url(forResource: "APIKey", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        
        return plist["APIKey"] as? String
    }
}

extension ARView {
    private static var _generativeModel: GenerativeModel?
    
    func setupGenerativeModel() {
        guard let apiKey = ConfigManager.loadAPIKey() else {
            fatalError("API Key must be set in APIKey.plist under 'APIKey'")
        }
        ARView._generativeModel = GenerativeModel(name: "gemini-1.5-pro-latest", apiKey: apiKey, requestOptions: RequestOptions(apiVersion: "v1beta"))
    }
    
    static func getGenerativeModel() -> GenerativeModel? {
        return _generativeModel
    }
    
    func addCoachingOverlay() {
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = self.session
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.goal = .horizontalPlane
        self.addSubview(coachingOverlay)
    }
}

struct ContentView: View {
    @State private var isProcessing = false
    @State private var isPopUpVisible = false
    @State private var objectName: String = ""
    @State private var textFieldInput: String = ""
    @State private var recallPrompt: String = ""
    @State private var recallReason: String = ""
    @State private var identificationInfo = ""
    @State private var verificationString = ""
    @State private var recallURL = ""
    @State private var positionSel: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    var objectPositions: [String: SIMD3<Float>] = [:]

    var body: some View {
        ZStack {
            ARViewContainer(isProcessing: $isProcessing, isPopUpVisible: $isPopUpVisible, objectName: $objectName, recallPrompt: $recallPrompt, textFieldInput: $textFieldInput, recallReason: $recallReason, identificationInfo: $identificationInfo, verificationString: $verificationString, recallURL: $recallURL, positionSel: $positionSel)
                .edgesIgnoringSafeArea(.all)
            
            if isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(10)
                    .tint(.white)
            }
            
            if isPopUpVisible {
                VStack {
                    Text(objectName)
                        .font(.title)
                        .bold()
                        .padding()
                    Text(recallPrompt)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    TextField("Enter Response", text: $textFieldInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    Button("Confirm"){
                        isPopUpVisible = false
                        let model = ARView.getGenerativeModel()
                        let verifyRecall = "\(objectName) has been recalled for the reason: \(recallReason), the piece of information that indentifies this recall is \(identificationInfo). The user responded to the prompt \(recallPrompt) with: \(textFieldInput). Is the product that the user owns part of the recall? (yes or no), if the user's response does not make sense return no."
                        Task {
                            do {
                                let verificationResponse = try await model?.generateContent(verifyRecall)
                                if let verificationConfirmation = verificationResponse?.text {
                                    print(verificationConfirmation)
                                    if verificationConfirmation.uppercased().contains("YES") {
                                        verificationString = "YES"
                                    } else if verificationConfirmation.uppercased().contains("NO") {
                                        verificationString = "NO"
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .frame(width: 350, height: 400)
                .background(Color.white.opacity(0.8))
                .cornerRadius(20)
                .shadow(radius: 10)
                .transition(.scale)
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var isProcessing: Bool
    @Binding var isPopUpVisible: Bool
    @Binding var objectName: String
    @Binding var recallPrompt: String
    @Binding var textFieldInput: String
    @Binding var recallReason: String
    @Binding var identificationInfo: String
    @Binding var verificationString: String
    @Binding var recallURL: String
    @Binding var positionSel: SIMD3<Float>
        
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        
        arView.setupGenerativeModel()
        arView.addCoachingOverlay()

        // Start plane detection
        startPlaneDetection(arView: arView)
        
        // Setup tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(recognizer:)))
        arView.addGestureRecognizer(tapGesture)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        if verificationString == "YES" {
            let texts = createTextCard(withText: objectName, withText: "Recalled!")
            placeTextEntities(arView: uiView, textEntities: texts, at: positionSel)
            verificationString = ""
            if let url = URL(string: recallURL) {
                UIApplication.shared.open(url)
            }
        } else if verificationString == "NO" {
            let texts = createTextCard(withText: objectName, withText: "Not Recalled")
            placeTextEntities(arView: uiView, textEntities: texts, at: positionSel)
            verificationString = ""
        }
    }
    
    // Function to start plane detection
    func startPlaneDetection(arView: ARView) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical] // Detect both horizontal and vertical planes
        configuration.environmentTexturing = .automatic // Optional: Enable environment texturing for more realistic rendering
        
        arView.session.run(configuration)
    }
    
    func createText(_ text: String, fontSize: CGFloat, position: SIMD3<Float>) -> ModelEntity {
        let textMesh = MeshResource.generateText(text,
                                                 extrusionDepth: 0.01,
                                                 font: .systemFont(ofSize: fontSize),
                                                 containerFrame: .zero,
                                                 alignment: .center,
                                                 lineBreakMode: .byWordWrapping)
        let textMaterial = SimpleMaterial(color: .white, isMetallic: false)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.scale = SIMD3<Float>(0.1, 0.1, 0.1)
        textEntity.position = position

        return textEntity
    }

    func createTextCard(withText titleText: String, withText recallText: String) -> [ModelEntity] {
        let titleEntity = createText(titleText, fontSize: 0.2, position: SIMD3<Float>(0, 0.02, 0))
        let expirationEntity = createText(recallText, fontSize: 0.2, position: SIMD3<Float>(0, 0, 0))
        
        return [titleEntity, expirationEntity]
    }

    func placeTextEntities(arView: ARView, textEntities: [ModelEntity], at location: SIMD3<Float>) {
        let textAnchor = AnchorEntity(world: location)
        textEntities.forEach { textEntity in
            textAnchor.addChild(textEntity)
        }
        arView.scene.addAnchor(textAnchor)
    }
    
    func placeObject(arView: ARView, object: ModelEntity, at location: SIMD3<Float>) {
        //create anchor = hooks virtual object to reality
        let objectAnchor = AnchorEntity(world: location)
        //tie model to anchor
        objectAnchor.addChild(object)
        //add anchor to scene
        arView.scene.addAnchor(objectAnchor)
    }
    
    func checkForRecall(objectName: String, completion: @escaping (Bool, String?, String?, String?) -> Void) {
        let ref = Database.database().reference(withPath: "2024/recalls")
        ref.observeSingleEvent(of: .value, with: { snapshot in
            var recallFound = false
            var recallReason: String?
            var identificationInfo: String?
            var recallURL: String?
            
            // Iterate over all recall entries under each recall ID
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot,
                   let dict = childSnapshot.value as? [String: Any] {
//                    print("Child Key: \(childSnapshot.key), Child Data: \(dict), Coincidence: \(dict["productName"] as! String == objectName)")
                    if let productName = dict["productName"] as? String,
                       productName == objectName {
                        recallReason = dict["recallReason"] as? String
                        identificationInfo = dict["identificationInfo"] as? String
                        recallURL = dict["url"] as? String
                        recallFound = true
                        break
                    }
                }
            }
            
            completion(recallFound, recallReason, identificationInfo, recallURL)
        }) { error in
            print(error.localizedDescription)
            completion(false, nil, nil, nil)
        }
    }



    
    class JSONDecoderUtility {
        // Decodes a given Data object into a specified Codable conforming type.
        static func decode<T: Codable>(type: T.Type, from jsonData: Data) -> T? {
            let decoder = JSONDecoder()
            do {
                return try decoder.decode(T.self, from: jsonData)
            } catch {
                print("Error decoding JSON: \(error)")
                return nil
            }
        }
    }
    
    class Coordinator: NSObject {
        var parent: ARViewContainer
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        @objc func handleTap(recognizer: UITapGestureRecognizer) {
            //touch location
            guard let arView = recognizer.view as? ARView, let model = ARView.getGenerativeModel() else { return }
            
            DispatchQueue.main.async {
                self.parent.isProcessing = true // Start the spinner
            }
            
            func captureCurrentFrame(arView: ARView) -> UIImage? {
                guard let currentFrame = arView.session.currentFrame else { return nil }
                
                let ciImage = CIImage(cvPixelBuffer: currentFrame.capturedImage)
                let context = CIContext()
                guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
                
                return UIImage(cgImage: cgImage)
            }
        
            
            let tapLocation = recognizer.location(in: arView)
//            print("Tap detected at location: \(tapLocation)")
//            print("Raycast results count: \(results.count)")

            if let firstResult = arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .horizontal).first {
                //3D point x,y,z coordinates.
                let worldPosition = simd_make_float3(firstResult.worldTransform.columns.3)

                
                if let capturedImage = captureCurrentFrame(arView: arView) {
                    let namePrompt = "Identify and return the following in JSON format considering the object visible in the camera view, 'objectName' (provide in format Brand - Object Name)"
                    Task {
                        do {
                            let response = try await model.generateContent(namePrompt, capturedImage)
                            DispatchQueue.main.async {
                                if let objectJSON = response.text {
                                    let cleanedJSON = objectJSON.replacingOccurrences(of: "```json", with: "")
                                                              .replacingOccurrences(of: "```", with: "")
                                    print(cleanedJSON)
                                    if let jsonData = cleanedJSON.data(using: .utf8),
                                       let product: Product = JSONDecoderUtility.decode(type: Product.self, from: jsonData) {
                                        self.parent.checkForRecall(objectName: product.objectName) { isRecalled, recallReason, identificationInfo, url in
                                            if isRecalled {
                                                self.parent.objectName = product.objectName
                                                
                                                let recallPrompt = "\(product.objectName) has been recalled for the reason: \(recallReason ?? "Not specified"), the piece of information that identifies this recall is \(identificationInfo ?? "Not specified"). Create a prompt for an user to provide the product information to see if their product is recalled via keyboard. One sentence only"
                                                Task {
                                                    do {
                                                        let recallResponse = try await model.generateContent(recallPrompt)
                                                        if let recallText = recallResponse.text {
                                                            self.parent.recallPrompt = recallText
                                                            self.parent.isPopUpVisible.toggle()
                                                            self.parent.isProcessing = false
                                                        }
                                                    }
                                                }
                                                
                                                self.parent.recallReason = recallReason ?? "Not specified"
                                                self.parent.identificationInfo = identificationInfo ?? "Not specified"
                                                self.parent.positionSel = worldPosition
                                                self.parent.recallURL = url ?? "Not specified"
                                            } else {
                                                let texts = self.parent.createTextCard(withText: product.objectName, withText: "Not Recalled")
                                                self.parent.placeTextEntities(arView: arView, textEntities: texts, at: worldPosition)
                                                self.parent.isProcessing = false
                                            }
                                        }
                                    }
                                } else {
                                    self.parent.isProcessing = false
                                }
                            }
                        } catch {
                            print("Error generating content: \(error)")
                            DispatchQueue.main.async {
                                self.parent.isProcessing = false
                            }
                        }
                    }
                }
            }
        }
    }
}


#Preview {
    ContentView()
}
