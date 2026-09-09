import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dart_des/dart_des.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SongSync',
      theme: ThemeData(primarySwatch: Colors.deepPurple, brightness: Brightness.dark),
      home: const SyncScreen(),
    );
  }
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final Strategy strategy = Strategy.P2P_STAR; 
  final String userName = "Device_${DateTime.now().millisecond}";
  Timer? _debounce;
  
  String connectedEndpointId = '';
  bool isHost = false;
  String statusText = "Ready";

  final AudioPlayer _player = AudioPlayer();
  final yt = YoutubeExplode();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _searchResults = [];
  bool isSearching = false;
  
  String? localFilePath;
  bool isDownloading = false;
  
  Video? currentVideo; 
  String? currentClientTitle;

  Map<int, String> incomingFiles = {};
  DateTime? connectionTime;
  
  bool isHostReady = false;
  bool isClientReady = false;
  int syncDelayMs = 0;
  int _syncNonce = 0;
  List<int> _latencies = [];
  int manualOffsetMs = 0;

  bool isPlayerExpanded = false;
  Map<String, dynamic>? currentSongMetadata;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();
  }

  // --- NETWORK LOGIC ---

  void hostGroup() async {
    setState(() {
      isHost = true;
      statusText = "Hosting... waiting for client.";
    });
    
    try {
      bool isLocationEnabled = await Permission.location.serviceStatus.isEnabled;
      if (!isLocationEnabled) {
        setState(() => statusText = "Error: Please turn on GPS/Location in your phone settings!");
        return;
      }
      
      await Nearby().stopAdvertising();
      await Nearby().startAdvertising(
        userName,
        strategy,
        onConnectionInitiated: (id, info) {
          Nearby().acceptConnection(
            id,
            onPayLoadRecieved: _onPayloadReceived,
            onPayloadTransferUpdate: _onPayloadTransferUpdate,
          );
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            setState(() {
              connectedEndpointId = id;
              statusText = "Connected to $userName";
              connectionTime = DateTime.now();
            });
            Nearby().stopAdvertising(); 
            
            _startLatencyMeasurement();
            
            // Manual play sync is required after a fresh connection.
          }
        },
        onDisconnected: (id) {
          setState(() {
            statusText = "Disconnected.";
            connectedEndpointId = '';
            connectionTime = null;
          });
        },
      );
    } catch (e) {
      setState(() => statusText = "Error hosting: $e");
    }
  }

  void joinGroup() async {
    setState(() {
      isHost = false;
      statusText = "Searching for host...";
    });

    try {
      bool isLocationEnabled = await Permission.location.serviceStatus.isEnabled;
      if (!isLocationEnabled) {
        setState(() => statusText = "Error: Please turn on GPS/Location in your phone settings!");
        return;
      }

      await Nearby().stopDiscovery();
      await Nearby().startDiscovery(
        userName,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          Nearby().requestConnection(
            userName,
            id,
            onConnectionInitiated: (id, info) {
              Nearby().acceptConnection(
                id,
                onPayLoadRecieved: _onPayloadReceived,
                onPayloadTransferUpdate: _onPayloadTransferUpdate,
              );
            },
            onConnectionResult: (id, status) {
              if (status == Status.CONNECTED) {
                setState(() {
                  connectedEndpointId = id;
                  statusText = "Connected to Host!";
                  connectionTime = DateTime.now();
                });
                Nearby().stopDiscovery();
                _startLatencyMeasurement();
              }
            },
            onDisconnected: (id) {
               setState(() {
                 connectionTime = null;
               });
            },
          );
        },
        onEndpointLost: (id) {},
      );
    } catch (e) {
      setState(() => statusText = "Error joining: $e");
    }
  }

  // --- SEARCH & DOWNLOAD LOGIC ---

  String activeSearchEngine = 'jiosaavn';

  Future<void> performSearch() async {
    if (_searchController.text.trim().isEmpty) return;
    // Removed FocusScope.of(context).unfocus(); as requested

    setState(() {
      isSearching = true;
      statusText = activeSearchEngine == 'jiosaavn' ? "Searching JioSaavn..." : "Searching YouTube...";
      _searchResults.clear();
    });

    try {
      if (activeSearchEngine == 'jiosaavn') {
        String query = Uri.encodeComponent(_searchController.text);
        var res = await Dio().get('https://www.jiosaavn.com/api.php?__call=search.getResults&q=$query&p=1&n=20&_format=json&_marker=0');
        var data = res.data is String ? jsonDecode(res.data) : res.data;
        List<dynamic> songs = data['results'] ?? [];

        setState(() {
          _searchResults = songs.where((s) => s['encrypted_media_url'] != null && s['encrypted_media_url'].toString().isNotEmpty).map((s) => {
            'engine': 'jiosaavn',
            'id': s['id'].toString(),
            'title': (s['song'] ?? s['title'] ?? '').toString().replaceAll('&quot;', '"'),
            'author': s['primary_artists'] ?? s['singers'] ?? s['music'] ?? 'Unknown Artist',
            'thumbnail': s['image']?.toString().replaceAll(RegExp(r'\d+x\d+'), '500x500') ?? '',
            'encrypted_media_url': s['encrypted_media_url'],
          }).toList();
          isSearching = false;
          statusText = "Found ${_searchResults.length} results on JioSaavn.";
        });
      } else {
        var results = await yt.search.search('${_searchController.text} audio');
        setState(() {
          _searchResults = results.take(20).map((video) => {
            'engine': 'youtube',
            'id': video.id.value,
            'title': video.title,
            'author': video.author,
            'thumbnail': video.thumbnails.highResUrl,
          }).toList();
          isSearching = false;
          statusText = "Found ${_searchResults.length} results on YouTube.";
        });
      }
    } catch (e) {
      setState(() {
        isSearching = false;
        statusText = "Search failed.";
      });
    }
  }

  Future<void> streamUniversalSong(Map<String, dynamic> songMap) async {
    FocusScope.of(context).unfocus();
    
    // Force pause so the new song doesn't auto-play prematurely before the handshake completes
    if (_player.playing) {
       await _player.pause();
    }
    
    setState(() {
      isDownloading = true;
      statusText = songMap['engine'] == 'jiosaavn' ? "Decrypting stream natively..." : "Extracting Stream URL...";
    });

    try {
      String directUrl = "";
      String engine = songMap['engine'];

      if (engine == 'jiosaavn') {
        String? encUrl = songMap['encrypted_media_url'];
        if (encUrl == null || encUrl.isEmpty) {
           throw Exception("This search result is an album or playlist, not a playable song.");
        }
        
        DES des = DES(key: utf8.encode("38346591"));
        List<int> decodedBase64 = base64.decode(encUrl);
        List<int> decrypted = des.decrypt(decodedBase64);
        directUrl = utf8.decode(decrypted).replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim().replaceAll('_96.mp4', '_320.mp4');
      } else if (engine == 'youtube') {
        StreamManifest? manifest;
        try {
          manifest = await yt.videos.streamsClient.getManifest(songMap['id']);
        } catch (e) {
          setState(() => statusText = "DRM Blocked! Searching alternatives...");
          var fallback = await yt.search.search('${songMap['title']} ${songMap['author']} lyric');
          for (var v in fallback.take(5)) {
             if (v.id.value == songMap['id']) continue;
             try {
                manifest = await yt.videos.streamsClient.getManifest(v.id.value);
                songMap['id'] = v.id.value;
                break;
             } catch (_) {}
          }
        }
        
        if (manifest == null) throw Exception("YouTube Extraction Blocked (IP Rate Limit or DRM).");
        var audioInfo = manifest.audioOnly.withHighestBitrate();
        directUrl = audioInfo.url.toString();
      }

      await _player.setUrl(directUrl);
      await _player.seek(Duration.zero);
      
      if (isHost) {
        isHostReady = true;
        if (connectedEndpointId.isNotEmpty) {
          Map<String, dynamic> command = {
            'action': 'stream_url', 
            'url': directUrl, 
            'fallback_url': directUrl,
            'title': songMap['title'],
            'author': songMap['author'],
            'thumbnail': songMap['thumbnail'],
          };
          Nearby().sendBytesPayload(connectedEndpointId, Uint8List.fromList(utf8.encode(jsonEncode(command))));
        } else {
          isClientReady = true; 
        }
        
        setState(() {
           isDownloading = false;
           currentSongMetadata = songMap;
           isPlayerExpanded = true;
        });
        
        _checkAndPlay();
      }
    } catch (e) {
      setState(() {
        isDownloading = false;
        statusText = "Extraction failed: ${e.toString().split('\n').first}";
      });
    }
  }

  Future<void> streamYouTubeSong(Map<String, dynamic> songMap) async {
    setState(() {
      isDownloading = true;
      statusText = "Extracting Stream URL...";
    });

    try {
      StreamManifest? manifest;
      String currentId = songMap['id'];
      
      try {
        manifest = await yt.videos.streamsClient.getManifest(currentId);
      } catch (e) {
        setState(() => statusText = "DRM Blocked! Searching alternatives...");
        // Fallback loop: try up to 5 different videos (lyrics, official, etc) to bypass DRM
        var fallback = await yt.search.search('${songMap['title']} ${songMap['author']} lyric');
        for (var v in fallback.take(5)) {
           if (v.id.value == songMap['id']) continue;
           try {
              manifest = await yt.videos.streamsClient.getManifest(v.id.value);
              currentId = v.id.value;
              break; // Success!
           } catch (_) {}
        }
      }
      
      if (manifest == null) throw Exception("All 5 fallback extractions blocked by Google.");

      var audioInfo = manifest.audioOnly.withHighestBitrate();
      String directUrl = audioInfo.url.toString();

      await _player.setUrl(directUrl);
      await _player.seek(Duration.zero);
      
      if (isHost) {
        isHostReady = true;
        if (connectedEndpointId.isNotEmpty) {
          Map<String, dynamic> command = {
            'action': 'load_yt', 
            'id': currentId,
            'title': songMap['title'],
            'author': songMap['author'],
            'thumbnail': songMap['thumbnail'],
          };
          Nearby().sendBytesPayload(connectedEndpointId, Uint8List.fromList(utf8.encode(jsonEncode(command))));
        } else {
          isClientReady = true; 
        }
        
        setState(() {
           isDownloading = false;
           currentSongMetadata = songMap;
           isPlayerExpanded = true;
        });
        
        _checkAndPlay();
      }
    } catch (e) {
      setState(() {
        isDownloading = false;
        statusText = "Extraction failed: ${e.toString().split('\n').first}";
      });
    }
  }

  void _startLatencyMeasurement() async {
    while (connectedEndpointId.isNotEmpty) {
      if (isHost) {
        int t0 = DateTime.now().millisecondsSinceEpoch;
        Map<String, dynamic> command = {
          'action': 'ping', 
          't0': t0,
          'position': _player.position.inMilliseconds,
          'playing': _player.playing
        };
        Nearby().sendBytesPayload(connectedEndpointId, Uint8List.fromList(utf8.encode(jsonEncode(command))));
      }
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  void _checkAndPlay() async {
    if (isHostReady && isClientReady) {
      _syncNonce++;
      int currentNonce = _syncNonce;
      
      int baseBuffer = 1000;
      
      if (connectedEndpointId.isNotEmpty) {
        int clientWait = baseBuffer - syncDelayMs;
        if (clientWait < 0) clientWait = 0;
        
        Map<String, dynamic> command = {
          'action': 'play', 
          'position': _player.position.inMilliseconds,
          'clientWait': clientWait, 
          'nonce': currentNonce
        };
        Nearby().sendBytesPayload(connectedEndpointId, Uint8List.fromList(utf8.encode(jsonEncode(command))));
      }
      
      int hostWait = baseBuffer - manualOffsetMs;
      if (hostWait < 0) hostWait = 0;
      await Future.delayed(Duration(milliseconds: hostWait));
      
      if (_syncNonce == currentNonce) {
        _player.play();
        setState(() => statusText = "Playing Stream in Sync!");
      }
      
      isHostReady = false;
      isClientReady = false;
    } else {
      setState(() => statusText = "Waiting for other device to buffer...");
    }
  }


  void togglePlayPause() async {
    _syncNonce++;
    int currentNonce = _syncNonce;
    
    if (_player.playing) {
      _player.pause();
      if (connectedEndpointId.isNotEmpty) {
        Map<String, dynamic> command = {'action': 'pause', 'nonce': currentNonce};
        Nearby().sendBytesPayload(connectedEndpointId, Uint8List.fromList(utf8.encode(jsonEncode(command))));
      }
    } else {
      int baseBuffer = 1000;
      
      if (connectedEndpointId.isNotEmpty) {
        int clientWait = baseBuffer - syncDelayMs;
        if (clientWait < 0) clientWait = 0;
        
        Map<String, dynamic> command = {
          'action': 'play', 
          'position': _player.position.inMilliseconds,
          'clientWait': clientWait, 
          'nonce': currentNonce
        };
        Nearby().sendBytesPayload(connectedEndpointId, Uint8List.fromList(utf8.encode(jsonEncode(command))));
      }
      
      int hostWait = baseBuffer - manualOffsetMs;
      if (hostWait < 0) hostWait = 0;
      await Future.delayed(Duration(milliseconds: hostWait));
      
      if (_syncNonce == currentNonce) {
        _player.play();
        setState(() => statusText = "Playing in Sync!");
      }
    }
  }

  // --- PAYLOAD RECEIVERS ---

  void _onPayloadReceived(String endpointId, Payload payload) async {
    if (payload.type == PayloadType.BYTES) {
      String msg = utf8.decode(payload.bytes!);
      var data = jsonDecode(msg);
      
        if (data['action'] == 'stream_url') {
          if (_player.playing) await _player.pause();
          
          setState(() {
            statusText = "Buffering stream from Host...";
            currentSongMetadata = {
              'title': data['title'],
              'author': data['author'],
              'thumbnail': data['thumbnail']
            };
            isPlayerExpanded = true;
          });
          
          await _player.setUrl(data['url']);
          await _player.seek(Duration.zero);
          
          setState(() => statusText = "Buffered! Waiting for Host...");
          Map<String, dynamic> command = {'action': 'client_ready'};
          Nearby().sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(command))));
          
        } else if (data['action'] == 'load_yt') {
          if (_player.playing) await _player.pause();
          
          setState(() {
            statusText = "Extracting URL from YouTube...";
            currentSongMetadata = {
              'id': data['id'],
              'title': data['title'],
              'author': data['author'],
              'thumbnail': data['thumbnail']
            };
            isPlayerExpanded = true;
          });
          
          try {
            StreamManifest? manifest;
            try {
              manifest = await yt.videos.streamsClient.getManifest(data['id']);
            } catch (e) {
               setState(() => statusText = "DRM Blocked! Searching alternatives...");
               var fallback = await yt.search.search('${data['title']} ${data['author']} lyric');
               for (var v in fallback.take(5)) {
                  if (v.id.value == data['id']) continue;
                  try {
                     manifest = await yt.videos.streamsClient.getManifest(v.id.value);
                     break;
                  } catch (_) {}
               }
            }
            if (manifest == null) throw Exception("All 5 fallback extractions blocked.");

            var audioInfo = manifest.audioOnly.withHighestBitrate();
            await _player.setUrl(audioInfo.url.toString());
            await _player.seek(Duration.zero);
            
            setState(() => statusText = "Buffered! Waiting for Host...");
            Map<String, dynamic> command = {'action': 'client_ready'};
            Nearby().sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(command))));
          } catch (e) {
            setState(() => statusText = "Extraction failed: ${e.toString().split('\n').first}");
          }
          
        } else if (data['action'] == 'client_ready') {
        isClientReady = true;
        _checkAndPlay();
      } else if (data['action'] == 'play') {
        int nonce = data['nonce'] ?? 0;
        _syncNonce = nonce;
        
        int finalWait = (data['clientWait'] ?? 0) - manualOffsetMs;
        
        if (data['position'] != null) {
          int hostPos = data['position'];
          int myPos = _player.position.inMilliseconds;
          int drift = myPos - hostPos;
          
          if (drift.abs() > 500) {
             // If drift is massive, fallback to physical seek
             _player.seek(Duration(milliseconds: hostPos));
          } else {
             // For standard pause drift, stagger the wait timer (no buffer flush!)
             finalWait += drift;
          }
        }
        
        if (finalWait < 0) finalWait = 0;
        if (finalWait > 0) {
           await Future.delayed(Duration(milliseconds: finalWait));
        }
        
        if (_syncNonce == nonce) {
          _player.play(); 
        }
      } else if (data['action'] == 'seek') {
        int nonce = data['nonce'] ?? 0;
        if (nonce > 0) _syncNonce = nonce;
        
        bool playAfter = data['playAfter'] ?? false;
        if (playAfter) _player.pause();
        
        await _player.seek(Duration(milliseconds: data['position']));
        
        if (playAfter) {
          Map<String, dynamic> command = {'action': 'client_ready'};
          Nearby().sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(command))));
        }
      } else if (data['action'] == 'pause') {
        int nonce = data['nonce'] ?? 0;
        _syncNonce = nonce;
        _player.pause();
      } else if (data['action'] == 'ping') {
        Map<String, dynamic> command = {'action': 'pong', 't0': data['t0']};
        Nearby().sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(command))));
        
        if (data['playing'] == false && _player.playing == true) {
          // Fallback: If host is paused but client is playing (e.g. dropped pause packet), force pause
          _player.pause();
        } else if (data['playing'] == true && _player.playing == false) {
          // Fallback: If host is playing but client is paused (e.g. dropped play packet), force play
          _player.seek(Duration(milliseconds: data['position'] + syncDelayMs));
          _player.play();
        }
      } else if (data['action'] == 'pong') {
        int t1 = DateTime.now().millisecondsSinceEpoch;
        int rtt = t1 - (data['t0'] as int);
        int latency = rtt ~/ 2;
        
        _latencies.add(latency);
        if (_latencies.length > 5) _latencies.removeAt(0); // keep last 5
        
        int avgLatency = ((_latencies.fold<int>(0, (a, b) => a + b)) / _latencies.length).toInt();
        setState(() {
          syncDelayMs = avgLatency;
        });
        
        Map<String, dynamic> updateCmd = {'action': 'update_latency', 'latency': avgLatency};
        Nearby().sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(updateCmd))));
      } else if (data['action'] == 'update_latency') {
        setState(() {
          syncDelayMs = data['latency'];
        });
      }
    } 
  }

  void _onPayloadTransferUpdate(String endpointId, PayloadTransferUpdate update) async {}



  Widget _buildMiniPlayer() {
    if (currentSongMetadata == null) return const SizedBox.shrink();
    
    return GestureDetector(
      onTap: () => setState(() => isPlayerExpanded = true),
      child: Container(
        height: 65,
        color: Colors.grey.shade900,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network((currentSongMetadata!['thumbnail'] ?? '').toString().replaceAll(RegExp(r'\d+x\d+'), '500x500'), width: 45, height: 45, cacheWidth: 135, cacheHeight: 135, fit: BoxFit.cover, filterQuality: FilterQuality.low, errorBuilder: (c,e,s) => const Icon(Icons.music_note)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(currentSongMetadata!['title'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(currentSongMetadata!['author'] ?? 'Unknown', style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isHost)
              StreamBuilder<bool>(
                stream: _player.playingStream,
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data ?? false;
                  return IconButton(
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: isDownloading ? null : togglePlayPause,
                  );
                }
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('SongSync')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("Status: $statusText", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                const SizedBox(height: 10),
                
                Row(
                  children: [
                    Expanded(child: ElevatedButton(onPressed: hostGroup, child: const Text("Host Group"))),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton(onPressed: joinGroup, child: const Text("Join Group"))),
                  ],
                ),
                const Divider(height: 20),
                
                if (isHost) ...[
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: const InputDecoration(labelText: "Search Song", border: OutlineInputBorder()),
                              onChanged: (text) {
                                if (_debounce?.isActive ?? false) _debounce!.cancel();
                                _debounce = Timer(const Duration(milliseconds: 500), () {
                                  if (text.trim().isNotEmpty) {
                                    performSearch();
                                  } else {
                                    setState(() {
                                      _searchResults = [];
                                      statusText = "Search cleared.";
                                    });
                                  }
                                });
                              },
                              onSubmitted: (_) {
                                if (_searchController.text.trim().isNotEmpty) performSearch();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: isSearching ? const CircularProgressIndicator() : const Icon(Icons.search),
                            onPressed: isSearching ? null : performSearch,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ChoiceChip(
                            label: const Text('JioSaavn'),
                            selected: activeSearchEngine == 'jiosaavn',
                            onSelected: (bool selected) {
                              if (selected) {
                                setState(() => activeSearchEngine = 'jiosaavn');
                                performSearch();
                              }
                            },
                          ),
                          const SizedBox(width: 16),
                          ChoiceChip(
                            label: const Text('YouTube'),
                            selected: activeSearchEngine == 'youtube',
                            onSelected: (bool selected) {
                              if (selected) {
                                setState(() => activeSearchEngine = 'youtube');
                                performSearch();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ] else ...[
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(child: Text("Waiting for Host to pick a song...", style: TextStyle(color: Colors.grey))),
                  ),
                ],
              ],
            ),
          ),
          
          Expanded(
            child: _searchResults.isNotEmpty 
              ? ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final songMap = _searchResults[index];
                    return ListTile(
                      onTap: isDownloading ? null : () => streamUniversalSong(songMap),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(songMap['thumbnail'] ?? '', width: 50, height: 50, cacheWidth: 150, cacheHeight: 150, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.music_note))
                      ),
                      title: Text(songMap['title'] ?? 'Unknown', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(songMap['author'] ?? 'Unknown'),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: isDownloading ? null : () => streamUniversalSong(songMap),
                      ),
                    );
                  },
                )
                : const Center(child: Text("Search for a song to begin playing")),
          ),
          
          _buildMiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildPlayerScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          onPressed: () => setState(() => isPlayerExpanded = false),
        ),
        title: Text(isHost ? "Host Player" : "Listening in Sync", style: const TextStyle(fontSize: 14, color: Colors.grey)),
        centerTitle: true,
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;
          
          Widget imageSection = Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                (currentSongMetadata!['thumbnail'] ?? '').toString().replaceAll(RegExp(r'\d+x\d+'), '500x500'), 
                width: isLandscape ? MediaQuery.of(context).size.height * 0.6 : MediaQuery.of(context).size.width * 0.8,
                height: isLandscape ? MediaQuery.of(context).size.height * 0.6 : MediaQuery.of(context).size.width * 0.8,
                cacheWidth: 800,
                cacheHeight: 800,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder: (c,e,s) => const Icon(Icons.music_note, size: 100)
              ),
            ),
          );

          Widget controlsSection = Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(currentSongMetadata!['title'] ?? 'Unknown', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(currentSongMetadata!['author'] ?? 'Unknown', style: const TextStyle(fontSize: 18, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
              
              const SizedBox(height: 30),
              
              StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final total = _player.duration ?? Duration.zero;
                  return Column(
                    children: [
                      Slider(
                        value: position.inSeconds.toDouble(),
                        max: total.inSeconds > 0 ? total.inSeconds.toDouble() : 1.0,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                        onChanged: (isHost && !isDownloading) ? (val) {
                          _player.seek(Duration(seconds: val.toInt()));
                        } : null,
                        onChangeEnd: (isHost && !isDownloading) ? (val) async {
                          _syncNonce++;
                          int currentNonce = _syncNonce;
                          
                          int posMs = val.toInt() * 1000;
                          bool wasPlaying = _player.playing;
                          
                          if (wasPlaying) {
                            _player.pause();
                            isHostReady = false;
                            isClientReady = false;
                          }
                          
                          if (connectedEndpointId.isNotEmpty) {
                            Map<String, dynamic> command = {
                              'action': 'seek', 
                              'position': posMs,
                              'playAfter': wasPlaying,
                              'nonce': currentNonce
                            };
                            Nearby().sendBytesPayload(connectedEndpointId, Uint8List.fromList(utf8.encode(jsonEncode(command))));
                          }
                          
                          await _player.seek(Duration(milliseconds: posMs));
                          
                          if (wasPlaying) {
                            isHostReady = true;
                            _checkAndPlay();
                          }
                        } : null,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.grey)),
                          Text("${total.inMinutes}:${(total.inSeconds % 60).toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ],
                  );
                },
              ),
              
              const SizedBox(height: 20),
              
              if (isHost)
                StreamBuilder<bool>(
                  stream: _player.playingStream,
                  builder: (context, snapshot) {
                    final isPlaying = snapshot.data ?? false;
                    return Center(
                      child: IconButton(
                        iconSize: 80,
                        icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                        onPressed: isDownloading ? null : togglePlayPause,
                      ),
                    );
                  }
                ),
                
              if (connectedEndpointId.isNotEmpty)
                Column(
                  children: [
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi, size: 16, color: syncDelayMs < 200 ? Colors.greenAccent : Colors.orangeAccent),
                          const SizedBox(width: 8),
                          Text(
                            "Auto-Sync Latency: ${syncDelayMs}ms", 
                            style: const TextStyle(fontSize: 12, color: Colors.grey)
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text("Hardware Echo Calibration", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Slider(
                      value: manualOffsetMs.toDouble(),
                      min: -300,
                      max: 300,
                      divisions: 60,
                      label: "${manualOffsetMs > 0 ? '+' : ''}${manualOffsetMs}ms",
                      activeColor: Colors.orangeAccent,
                      inactiveColor: Colors.white10,
                      onChanged: (val) {
                        setState(() => manualOffsetMs = val.toInt());
                      }
                    ),
                  ],
                ),
            ],
          );

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: isLandscape
              ? Row(
                  children: [
                    Expanded(child: imageSection),
                    const SizedBox(width: 40),
                    Expanded(
                      child: SingleChildScrollView(
                        child: controlsSection,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: imageSection),
                    const SizedBox(height: 20),
                    controlsSection,
                    const SizedBox(height: 40),
                  ],
                ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool showPlayer = isPlayerExpanded && currentSongMetadata != null;
    return PopScope(
      canPop: !isPlayerExpanded,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isPlayerExpanded) {
          setState(() => isPlayerExpanded = false);
        }
      },
      child: Stack(
        children: [
          _buildHomeScreen(),
          
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            top: showPlayer ? 0 : MediaQuery.of(context).size.height,
            bottom: showPlayer ? 0 : -MediaQuery.of(context).size.height,
            left: 0,
            right: 0,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
                  setState(() => isPlayerExpanded = false);
                }
              },
              child: _buildPlayerScreen(),
            ),
          ),
        ],
      ),
    );
  }
}
