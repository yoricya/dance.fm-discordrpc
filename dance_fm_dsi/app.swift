//
//  app.swift
//  dance_fm_dsi
//
//  Created by Ярослав on 07.06.2025.
//

import Foundation
import AVFoundation
import MediaPlayer

func new_app() -> TrackApp? {
    let app = TrackApp()
    
    app.rpc = RPC_connector(appId: "1380964853769830511", api: app)
    app.rpc?.reconnect()
    
    return app
}

class TrackState {
    public var name = ""
    public var author = ""
    
    public var title = ""
    public var is_playing = false
}

class ObservableStateData: ObservableObject  {
    @Published public var title = ""
    @Published public var is_playing = false
    @Published public var live_latency = 0
    @Published public var rpc_status = "Disconnected"
}

class TrackApp {
    public var state = TrackState()
    public var observe_state = ObservableStateData()

    public var audio = AudioPlayerManager(url: "https://streams.dancefm.net/aac-hq")
    public var rpc: RPC_connector?
    
    init() {
        audio.app = self
    }
    
    public var is_avail = false
    public func start_title_update(){
        is_avail = true
        Task {
            while is_avail {
                fetchTrackInfo()
                print("refetching title..")
                try await Task.sleep(nanoseconds: 8 * 1_000_000_000)
            }
        }
    }
    
    public func play_pause() {
        if !state.is_playing {
            self.set_playing_status(s: true)
            
            start_title_update()
            audio.playStream()
        } else {
            is_avail = false
            audio.stopStream()
        }
        
        print(state.is_playing)
    }
    
    func set_playing_status(s: Bool) {
        state.is_playing = s
        
        DispatchQueue.main.async {
            self.audio.setPlayingStatus(isPlaying: s)
            self.observe_state.is_playing = s
        }
    }
    
    func set_rpc_status(s: String) {
        DispatchQueue.main.async {
            self.observe_state.rpc_status = s
        }
    }
    
    public func reset_state() {
        state.title = ""
        state.name = ""
        state.author = ""
        
        DispatchQueue.main.async {
            self.observe_state.title = ""
            self.observe_state.live_latency = 0
        }
        
        audio.stopStream()
        audio.player = nil
    }
    
    func fetchTrackInfo() {
        var request = URLRequest(url: URL(string: "https://dance.fm/js/stream-icy-meta.php")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "url=https://streams.dancefm.net/aac-hq".data(using: .utf8)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("post request error: ", error)
                return
            }
            
            if let responseString = String(data: data, encoding: .utf8){
                if self.audio.app?.state.title != responseString {
                    print("new title: "+responseString)
                    
                    DispatchQueue.main.async {
                        self.audio.app?.observe_state.title = responseString
                    }
                    
                    self.audio.app?.state.title = responseString
                    
                    let sep_title = responseString.components(separatedBy: " - ")
                    self.audio.app?.state.author = sep_title[0]
                    if sep_title.count > 1 {
                        self.audio.app?.state.name = sep_title[1]
                    }
                    
                    if let app = self.audio.app {
                        DispatchQueue.main.async {
                            self.audio.updateNowPlaying(title: app.state.name, artist: app.state.author)
                        }
                    }
                }
                
            }
        }
        
        task.resume()
    }
    
    public func to_hash() -> String {
        return state.title
    }
}

class AudioPlayerManager: NSObject, ObservableObject {
    public var url: String
    var app: TrackApp?
    var player: AVPlayer?

    init(url: String) {
        self.url = url
        super.init()
        setupNowPlaying()
    }

    func playStream() {
        guard let streamURL = URL(string: url) else {
            print("incorrect url.")
            return
        }

        if player == nil {
            player = AVPlayer(url: streamURL)
                        
            player?.volume = 1.0
            player?.addObserver(self, forKeyPath: #keyPath(AVPlayer.rate), options: [.new], context: nil)
            player?.addObserver(self, forKeyPath: #keyPath(AVPlayer.status), options: [.new], context: nil)
        }
        
        // Check Live Latency
        let lat = checkLatency()
        if lat > 1 {
            DispatchQueue.main.async {
                self.app?.observe_state.live_latency = Int(lat)
            }
        }
        
        player?.play()
        print("started playing.")
    }
    
    func checkLatency() -> Double {
        guard let player = player else { return -1 }

        if let currentItem = player.currentItem {
            let currentTime = currentItem.currentTime().seconds

            // Загруженные диапазоны
            let loadedRanges = currentItem.loadedTimeRanges
            if let firstRange = loadedRanges.first as? CMTimeRange {
                let availableDuration = CMTimeGetSeconds(firstRange.duration)
                let latency = availableDuration - currentTime
                return latency
            }
        }
        
        return -1
    }

    func stopStream() {
        player?.pause()
        print("stopped playing.")
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if self.player?.rate == 0 {
            app?.set_playing_status(s: false)
        } else {
            app?.set_playing_status(s: true)
        }
    }

    private func setupNowPlaying() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [unowned self] _ in
            if !isPlaying() {
                self.app?.play_pause()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [unowned self] _ in
            if isPlaying() {
                self.app?.play_pause()
            }
            return .success
        }
        
    }

    private func isPlaying() -> Bool {
        return player?.rate != 0
    }

    func updateNowPlaying(title: String, artist: String) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func setPlayingStatus(isPlaying: Bool) {
        if isPlaying {
            MPNowPlayingInfoCenter.default().playbackState = .playing
        } else {
            MPNowPlayingInfoCenter.default().playbackState = .paused
        }
    }
}

public class RPC_connector {
    public let rpc: SwordRPC
    let api: TrackApp
    
    var dispatchTimer: DispatchSourceTimer?
    var old_track_hash: String?
    public var is_gateway_connected = false
    
    public var is_reconnecting_now = false
    public var reconnect_attempts = 0
    
    init(appId: String, api: TrackApp) {
        self.rpc = SwordRPC(appId: appId, handlerInterval: 500)
        self.api = api
        
        rpc.onConnect { rpc in
            self.is_gateway_connected = true
            self.reconnect_attempts = 0
            
            print("[Discord-Connector] RPC Connected")
            self.api.set_rpc_status(s: "Connected")
            self.startUpdating()
        }
        
        rpc.onDisconnect { rpc, code, msg in
            self.is_gateway_connected = false
            
            self.stopUpdating()
            self.api.set_rpc_status(s: "Disconnected")
            print("[Discord-Connector] RPC disconnected: \(String(describing: msg)) (\(String(describing: code)))")
        }
        
        rpc.onError { rpc, code, msg in
            self.is_gateway_connected = false
            
            self.stopUpdating()
            self.api.set_rpc_status(s: "Error")
            print("[Discord-Connector] RPC error: \(String(describing: msg)) (\(String(describing: code)))")
        }
    }
    
    func reconnect() {
        self.old_track_hash = nil
        is_reconnecting_now = true
        self.api.set_rpc_status(s: "Reconnect")
        rpc.disconnect()
        if !rpc.connect() && reconnect_attempts <= 4 {
            reconnect_attempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.reconnect()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.is_reconnecting_now = false
        }
    }
    
    func startUpdating() {
        print("[Discord-Connector] start updating...")
        
        dispatchTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        dispatchTimer?.schedule(deadline: .now(), repeating: 1.0)
        
        dispatchTimer?.setEventHandler {
            if !self.api.state.is_playing && self.old_track_hash != nil {
                self.old_track_hash = nil
                self.rpc.reset_presence()
                print("[Discord-Connector] Reset track")
            }
            
            if !self.api.state.is_playing || !self.is_gateway_connected {
                return
            }
            
            if self.old_track_hash != nil && self.api.to_hash() == self.old_track_hash! {
                return
            }
            
            self.old_track_hash = self.api.to_hash()
            
            print("[Discord-Connector] Update track")
            
            var presence = RichPresence()
            presence.type = 2
            presence.state = self.api.state.author
            presence.details = self.api.state.name
            presence.buttons = [RichPresence.Button(label: "The Beat Of Amsterdam", url: "https://dance.fm/")]

            
            //  presence.timestamps = RichPresence.Timestamps(end: Date(timeIntervalSince1970: TimeInterval(self.api.end_timestamp / 1000)), start: Date(timeIntervalSince1970: TimeInterval(self.api.start_timestamp / 1000)) as Date)
            
            // Set image
            //if self.api.album_image_link != nil {
            //    presence.assets = RichPresence.Assets(largeImage: self.api.album_image_link)
            //}
            
            self.rpc.set_presence(pr: presence)
        }
        
        dispatchTimer?.resume()
    }
    
    func stopUpdating() {
        dispatchTimer?.cancel()
        dispatchTimer = nil
    }
}
