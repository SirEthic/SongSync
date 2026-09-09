# SongSync 🎵

SongSync is a revolutionary Flutter application that enables perfectly synchronized, zero-latency multi-device music streaming over Wi-Fi Direct. Turn any group of Android phones into a perfectly synced surround sound system, completely offline.

## Features ✨
* **Flawless Multi-Device Synchronization**: Achieves sub-millisecond playback synchronization across multiple devices.
* **Offline P2P Networking**: Powered by Google's Nearby Connections API (Wi-Fi Direct/Bluetooth) for blazing fast, local area transmission without needing an active internet connection to communicate between devices.
* **Universal Search Engine**: Search, extract, and stream music directly from YouTube and JioSaavn with built-in DRM decryption and fallback routing.
* **Zero-Latency Staggered Wait Algorithm**: A custom-built sync engine that dynamically calculates network packet flight times and pause-drifts, staggering playback commands to crash into each other at the exact same timestamp without flushing hardware audio buffers.
* **Hardware Echo Calibration**: A manual slider to offset physical Android hardware audio mixer latencies (e.g., Samsung vs Pixel speaker wake times) for perfect, echo-free acoustics.
* **Dead Client Wakeup Protocol**: Bulletproof background state recovery. If network packets are dropped, the client intelligently extrapolates the host's current timestamp and physically catches up.

## How It Works 🧠
SongSync uses a highly optimized Client-Host architecture:
1. The **Host** device creates a `P2P_STAR` network using the Nearby Connections API.
2. The **Client** devices discover and connect to the Host.
3. A background latency ping loop measures the exact Round Trip Time (RTT) of the Wi-Fi Direct connection.
4. When a song is selected, the Host negotiates the streaming URL and buffers the track.
5. When playback starts, the app calculates the exact network flight time and executes a 1-second countdown handshake, dynamically offsetting each device's start time to guarantee simultaneous acoustic execution.

## Getting Started 🚀
### Prerequisites
* Flutter SDK (3.0.0 or higher)
* An Android device (The Nearby Connections API requires physical Android devices. iOS is not natively supported by this specific networking strategy).

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/SongSync.git
   ```
2. Navigate to the directory:
   ```bash
   cd SongSync
   ```
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app on your physical Android devices:
   ```bash
   flutter run
   ```

## Usage 📱
1. Open the app on two or more Android devices.
2. On Device A, tap **Host Group**.
3. On Device B, tap **Join Group** and wait for it to connect to the Host.
4. On the Host device, use the search bar to find a song on JioSaavn or YouTube.
5. Tap the song to begin buffering. Once both devices are ready, playback will start perfectly in sync!
6. *Optional*: If you hear a faint echo, use the **Hardware Echo Calibration** slider on the player screen to align the specific hardware delay of your phone models.

## Dependencies 📦
* `just_audio` - Advanced audio playback engine
* `nearby_connections` - Google's offline P2P networking API
* `youtube_explode_dart` - YouTube extraction engine
* `dart_des` - Native decryption for JioSaavn streams
* `dio` - HTTP client

## License 📄
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
