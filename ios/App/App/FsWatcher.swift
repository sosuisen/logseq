//
//  FsWatcher.swift
//  Logseq
//
//  Created by Mono Wang on 2/17/R4.
//

import Foundation
import Capacitor
import DirectoryWatcher

// MARK: Watcher Plugin

@objc(FsWatcher)
public class FsWatcher: CAPPlugin, PollingWatcherDelegate {
    private var watcher: PollingWatcher? = nil
    private var baseUrl: URL? = nil
    
    override public func load() {
        print("debug FsWatcher iOS plugin loaded!")
    }
    
    @objc func watch(_ call: CAPPluginCall) {
        if let path = call.getString("path") {
            guard let url = URL(string: path) else {
                call.reject("can not parse url")
                return
            }
            self.baseUrl = url
            self.watcher = PollingWatcher(at: url)
            self.watcher?.delegate = self
            
            call.resolve(["ok": true])
            
        } else {
            call.reject("missing path string parameter")
        }
    }
    
    @objc func unwatch(_ call: CAPPluginCall) {
        watcher?.stop()
        watcher = nil
        baseUrl = nil
        
        call.resolve()
    }
    
    public func recevedNotification(_ url: URL, _ event: PollingWatcherEvent, _ metadata: SimpleFileMetadata?) {
        // print("debug watcher \(event) \(url) ")
        let allowedPathExtensions: Set = ["md", "markdown", "org", "css", "edn", "excalidraw"]
        if !allowedPathExtensions.contains(url.pathExtension.lowercased()) {
            return
        }
        switch event {
            // NOTE: Event in js {dir path content stat{mtime}}
        case .Unlink:
            self.notifyListeners("watcher", data: ["event": "unlink",
                                                   "dir": baseUrl?.description as Any,
                                                   "path": url.description,
                                                  ])
        case .Add:
            let content = try? String(contentsOf: url, encoding: .utf8)
            self.notifyListeners("watcher", data: ["event": "add",
                                                   "dir": baseUrl?.description as Any,
                                                   "path": url.description,
                                                   "content": content as Any,
                                                   "stat": ["mtime": metadata?.contentModificationTimestamp,
                                                            "ctime": metadata?.creationTimestamp]
                                                  ])
        case .Change:
            let content = try? String(contentsOf: url, encoding: .utf8)
            self.notifyListeners("watcher", data: ["event": "change",
                                                   "dir": baseUrl?.description as Any,
                                                   "path": url.description,
                                                   "content": content as Any,
                                                   "stat": ["mtime": metadata?.contentModificationTimestamp,
                                                            "ctime": metadata?.creationTimestamp]])
        case .Error:
            // TODO: handle error?
            break
        }
    }
}

// MARK: PollingWatcher

public protocol PollingWatcherDelegate {
    func recevedNotification(_ url: URL, _ event: PollingWatcherEvent, _ metadata: SimpleFileMetadata?)
}

public enum PollingWatcherEvent: String {
    case Add
    case Change
    case Unlink
    case Error
}

public struct SimpleFileMetadata: CustomStringConvertible, Equatable {
    var contentModificationTimestamp: Double
    var creationTimestamp: Double
    var fileSize: Int
    
    public var description: String {
        return "Meta(size=\(self.fileSize), mtime=\(self.contentModificationTimestamp), ctime=\(self.creationTimestamp)"
    }
}

public class PollingWatcher {
    private let url: URL
    public var delegate: PollingWatcherDelegate? = nil
    private var metaDb: [URL: SimpleFileMetadata] = [:]
    private var timer: DispatchSourceTimer?
    
    public init?(at: URL) {
        self.url = at
        
        let queue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".timer")
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer!.schedule(deadline: .now(), repeating: .seconds(2))
        timer!.setEventHandler { [weak self] in
            self?.tick()
        }
        timer!.resume()
    }
    
    deinit {
        self.stop()
    }
    
    public func stop() {
        timer?.cancel()
        timer = nil
    }
    
    private func tick() {
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            
            var newMetaDb: [URL: SimpleFileMetadata] = [:]
            
            for case let fileURL as URL in enumerator {
                do {
                    let fileAttributes = try fileURL.resourceValues(forKeys:[.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey])
                    if fileAttributes.isRegularFile! {
                        let meta = SimpleFileMetadata(
                            contentModificationTimestamp: fileAttributes.contentModificationDate?.timeIntervalSince1970 ?? 0.0,
                            creationTimestamp: fileAttributes.creationDate?.timeIntervalSince1970 ?? 0.0,
                            fileSize: fileAttributes.fileSize ?? 0)
                        newMetaDb[fileURL] = meta
                    }
                } catch {
                    // TODO: handle error?
                }
            }
            
            self.updateMetaDb(with: newMetaDb)
        }
    }
    
    // TODO: batch?
    private func updateMetaDb(with newMetaDb: [URL: SimpleFileMetadata]) {
        for (url, meta) in newMetaDb {
            if let idx = self.metaDb.index(forKey: url) {
                let (_, oldMeta) = self.metaDb.remove(at: idx)
                if oldMeta != meta {
                    self.delegate?.recevedNotification(url, .Change, meta)
                }
            } else {
                self.delegate?.recevedNotification(url, .Add, meta)
            }
        }
        for url in self.metaDb.keys {
            self.delegate?.recevedNotification(url, .Unlink, nil)
        }
        self.metaDb = newMetaDb
    }
}
