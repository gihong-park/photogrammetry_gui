//
//  ContentView.swift
//  Shared
//
//  Created by KiHong Park on 2021/10/22.
//

import SwiftUI
import RealityKit
import Foundation
import os

private let logger = Logger(subsystem: "com.oldrookiecorp.photometry.photometry",
                            category: "HelloPhotogrammetry")
@available(macOS 12.0, *)
struct ContentView: View {
    @State var url:URL?
    @State var progress:Double = 0
    var body: some View {
        return VStack {
            DroppableArea( url: $url, progress:$progress)
           
            Text(url?.lastPathComponent ?? "please drag and drop folder to white box above")
                .background(Color.white)
                .foregroundColor(Color.black)
                .padding(.all, 10)
            Text(String(format: "%.2f", progress))
                .background(Color.white)
                .foregroundColor(Color.black)
                .padding(.all, 10)

        }.padding(40)
    }
    
    struct DragableImage: View {
        let url: URL
        
        var body: some View {
            Image(nsImage: NSImage(byReferencing: url))
                .resizable()
                .frame(width: 150, height: 150)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .padding(2)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.1)))
                .shadow(radius: 3)
                .padding(4)
                .onDrag { return NSItemProvider(object: self.url as NSURL) }
        }
    }
    
    struct DroppableArea: View {
        @Binding var url: URL?
        @State var active: Bool = false
        @Binding var progress:Double
        var body: some View {
            let dropDelegate = MyDropDelegate(url: $url, progress: $progress, active: $active)
            return VStack {
                HStack {
                    Text("Drag and Drop Folder")
                        .foregroundColor(Color.black)
                        .frame(width: 200.0, height: 200.0)
                }
                .padding(.all)
            }
            .border(Color.black)
            .background( Rectangle().fill(active ? Color.green:Color.white))
            .frame(width: 300, height: 300.0)
            .onDrop(of: ["public.file-url"], delegate: dropDelegate)
        }
    }
    
    struct GridCell: View {
        let active: Bool
        let url: URL?

        var body: some View {
            return Rectangle()
                .fill(self.active ? Color.green : Color.clear)
                .frame(width: 150, height: 150)
        }
    }
    
    struct MyDropDelegate: DropDelegate {
        @Binding var url: URL?
        @Binding var progress: Double
        @Binding var active: Bool
        func validateDrop(info: DropInfo) -> Bool {
            return info.hasItemsConforming(to: ["public.file-url"])
        }
        
        func dropEntered(info: DropInfo) {
            NSSound(named: "Morse")?.play()
        }
        
        func performDrop(info: DropInfo) -> Bool {
            NSSound(named: "Submarine")?.play()
            let items = info.itemProviders(for: ["public.file-url"])
            
            for item in items {
                item.loadItem(forTypeIdentifier: "public.file-url", options: nil) {
                    (urlData, error) in DispatchQueue.main.async {
                        if let urlData = urlData as? Data {
                            url = NSURL(absoluteURLWithDataRepresentation: urlData, relativeTo: nil) as URL
                            
                            let configuration = makeConfiguration()
                            logger.log("using configuration: \(String(describing: configuration))")
                            
                            var maybeSession: PhotogrammetrySession? = nil
                            do {
                                maybeSession = try PhotogrammetrySession(input: url!,
                                                                         configuration: configuration)
                                logger.log("Successfully created session.")
                            } catch {
                                logger.error("Error creating session: \(String(describing: error))")
                                Foundation.exit(1)
                            }
                            guard let session = maybeSession else {
                                Foundation.exit(1)
                            }
                            
                            let waiter = Task {
                                do {
                                    for try await output in session.outputs {
                                        switch output {
                                            case .processingComplete:
                                                logger.log("Processing is complete!")
                                                Foundation.exit(0)
                                            case .requestError(let request, let error):
                                                logger.error("Request \(String(describing: request)) had an error: \(String(describing: error))")
                                            case .requestComplete(let request, let result):
                                                handleRequestComplete(request: request, result: result)
                                            case .requestProgress(let request, let fractionComplete):
                                                progress = fractionComplete
                                                handleRequestProgress(request: request,
                                                                        fractionComplete: fractionComplete)
                                            case .inputComplete:  // data ingestion only!
                                                logger.log("Data ingestion is complete.  Beginning processing...")
                                            case .invalidSample(let id, let reason):
                                                logger.warning("Invalid Sample! id=\(id)  reason=\"\(reason)\"")
                                            case .skippedSample(let id):
                                                logger.warning("Sample id=\(id) was skipped by processing.")
                                            case .automaticDownsampling:
                                                logger.warning("Automatic downsampling was applied!")
                                            case .processingCancelled:
                                                logger.warning("Processing was cancelled.")
                                            @unknown default:
                                                logger.error("Output: unhandled message: \(output.localizedDescription)")

                                        }
                                    }
                                } catch {
                                    logger.error("Output: ERROR = \(String(describing: error))")
                                    Foundation.exit(0)
                                }
                            }
                            
                            withExtendedLifetime((session, waiter)) {
                                // Run the main process call on the request, then enter the main run
                                // loop until you get the published completion event or error.
                                do {
                                    let request = makeRequestFromArguments(outputUrl: URL(fileURLWithPath:  url!.deletingLastPathComponent().path + "/outputs/"+url!.lastPathComponent + ".usdz"))
                                    logger.log("Using request: \(String(describing: request))")
                                    try session.process(requests: [ request ])
                                    logger.log("next process")
                                    // Enter the infinite loop dispatcher used to process asynchronous
                                    // blocks on the main queue. You explicitly exit above to stop the loop.
                                    RunLoop.main.run()
                                } catch {
                                    logger.critical("Process got error: \(String(describing: error))")
//                                    Foundation.exit(1)
                                }
                            }
                        }
                    }
                }
            }
            return true
        }
        
        func dropUpdated(info: DropInfo) -> DropProposal? {
            self.active = true
                        
            return nil
        }
        
        func dropExited(info: DropInfo) {
            self.active = false
        }
    }
}

@available(macOS 12.0, *)
private func makeRequestFromArguments(outputUrl: URL) -> PhotogrammetrySession.Request {
    return PhotogrammetrySession.Request.modelFile(url: outputUrl, detail:
                                                    PhotogrammetrySession.Request.Detail.full)
}
@available(macOS 12.0, *)
func makeConfiguration() -> PhotogrammetrySession.Configuration {
    var configuration = PhotogrammetrySession.Configuration()
    configuration.featureSensitivity = .high
    configuration.sampleOrdering = .unordered
    
    return configuration
}
@available(macOS 12.0, *)
func handleRequestComplete(request: PhotogrammetrySession.Request,
                                          result: PhotogrammetrySession.Result) {
    logger.log("Request complete: \(String(describing: request)) with result...")
    switch result {
        case .modelFile(let url):
            logger.log("\tmodelFile available at url=\(url)")
        default:
            logger.warning("\tUnexpected result: \(String(describing: result))")
    }
}
/// Called when the sessions sends a progress update message.
@available(macOS 12.0, *)
func handleRequestProgress(request: PhotogrammetrySession.Request,
                                          fractionComplete: Double) {
    logger.log("Progress(request = \(String(describing: request)) = \(fractionComplete)")
}


@available(macOS 12.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
