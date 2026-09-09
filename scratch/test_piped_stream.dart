import 'package:dio/dio.dart';
import 'dart:convert';
void main() async {
  var instances = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.smnz.de',
    'https://pi.ggtyler.dev/api',
    'https://piped-api.lunar.icu',
    'https://de.piped.cf',
    'https://pipedapi.drgns.space'
  ];
  for (var url in instances) {
    try {
      var res = await Dio().get('$url/streams/ol6mmFtZbJY');
      var data = res.data is String ? jsonDecode(res.data) : res.data;
      if (data['audioStreams'] != null) {
        print('SUCCESS: $url');
      }
    } catch (e) {}
  }
}
