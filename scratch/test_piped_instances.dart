import 'package:dio/dio.dart';
import 'dart:convert';
void main() async {
  var instances = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.smnz.de',
    'https://pi.ggtyler.dev/api',
    'https://piped-api.lunar.icu'
  ];
  for (var url in instances) {
    try {
      var res = await Dio().get('$url/search?q=test&filter=music_songs');
      var data = res.data is String ? jsonDecode(res.data) : res.data;
      print('SUCCESS: $url');
    } catch (e) {
      print('FAIL: $url');
    }
  }
}
