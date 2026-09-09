import 'package:dio/dio.dart';

void main() async {
  try {
    var res = await Dio().get('https://api-v2.soundcloud.com/search/tracks?q=believer&client_id=Pb72ranhoyt6gw7hM7TkzUItXlMWSNSo&limit=20');
    var tracks = res.data['collection'] as List<dynamic>;
    
    var results = tracks.map((t) => {
      'id': t['id'].toString(),
      'title': t['title'],
      'author': t['user']?['username'] ?? 'Unknown Artist',
      'thumbnail': t['artwork_url']?.replaceAll('-large', '-t500x500') ?? t['user']?['avatar_url']?.replaceAll('-large', '-t500x500') ?? '',
      'trackInfo': t
    }).toList();
    
    print('Success: ${results.length}');
  } catch (e, st) {
    print(e);
    print(st);
  }
}
