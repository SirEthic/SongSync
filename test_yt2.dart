import 'package:youtube_explode_dart/youtube_explode_dart.dart'; 
void main() async { 
  var yt = YoutubeExplode(); 
  var search = await yt.search.search('Fineapple by Pineapple Express audio'); 
  var video = search.first; 
  print(video.title); 
  print(video.id.value); 
  try { 
    var manifest = await yt.videos.streamsClient.getManifest(video.id.value); 
    print(manifest.audioOnly.withHighestBitrate().url); 
  } catch (e) { 
    print('Failed: ' + e.toString()); 
  } 
  yt.close(); 
}
