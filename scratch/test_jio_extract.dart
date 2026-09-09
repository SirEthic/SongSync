import 'package:dio/dio.dart';
import 'dart:convert';
void main() async {
  try {
    var dio = Dio();
    var res = await dio.get('https://www.jiosaavn.com/api.php?__call=search.getResults&q=believer&p=1&n=2&_format=json&_marker=0');
    var data = res.data is String ? jsonDecode(res.data) : res.data;
    print(data['results'][0]);
  } catch (e) {
    print(e);
  }
}
