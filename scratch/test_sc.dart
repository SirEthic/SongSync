import 'package:dio/dio.dart';

void main() async {
  var dio = Dio();
  try {
    var res = await dio.get('https://soundcloud.com');
    var html = res.data.toString();
    var scriptMatches = RegExp(r'<script crossorigin src="(https:\/\/a-v2\.sndcdn\.com\/assets\/.*?\.js)"><\/script>').allMatches(html);
    
    for (var match in scriptMatches) {
      var jsUrl = match.group(1);
      var jsRes = await dio.get(jsUrl!);
      var jsCode = jsRes.data.toString();
      var idMatch = RegExp(r'client_id:"([a-zA-Z0-9]{32})"').firstMatch(jsCode);
      if (idMatch != null) {
        print('FOUND CLIENT ID: ${idMatch.group(1)}');
        
        // Let's test searching for a song using this ID
        var clientId = idMatch.group(1);
        var searchRes = await dio.get('https://api-v2.soundcloud.com/search/tracks?q=pineapple%20express&client_id=$clientId&limit=3');
        
        var tracks = searchRes.data['collection'];
        for (var track in tracks) {
          print(track['title']);
          print('Artwork: ${track['artwork_url']}');
          
          // Test fetching stream URL
          var transcodings = track['media']['transcodings'];
          for (var trans in transcodings) {
             if (trans['format']['protocol'] == 'hls' || trans['format']['protocol'] == 'progressive') {
                var streamRes = await dio.get(trans['url'] + '?client_id=$clientId');
                print('Stream URL: ${streamRes.data['url']}');
                break;
             }
          }
        }
        break;
      }
    }
  } catch (e) {
    print(e);
  }
}
