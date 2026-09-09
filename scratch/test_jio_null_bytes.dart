import 'package:dio/dio.dart';
import 'package:dart_des/dart_des.dart';
import 'dart:convert';
void main() async {
  try {
    var dio = Dio();
    var res = await dio.get('https://www.jiosaavn.com/api.php?__call=search.getResults&q=faded&p=1&n=1&_format=json&_marker=0');
    var data = res.data is String ? jsonDecode(res.data) : res.data;
    String encUrl = data['results'][0]['encrypted_media_url'];
    
    DES des = DES(key: utf8.encode('38346591'));
    List<int> decodedBase64 = base64.decode(encUrl);
    List<int> decrypted = des.decrypt(decodedBase64);
    String directUrl = utf8.decode(decrypted).replaceAll('\x00', '').replaceAll('\x08', '').trim();
    print('URL Length: ${directUrl.length}');
    print('URL: $directUrl');
    
    var hres = await dio.head(directUrl);
    print('Raw status: ${hres.statusCode}');
    var hres320 = await dio.head(directUrl.replaceAll('_96.mp4', '_320.mp4'));
    print('320 status: ${hres320.statusCode}');
  } catch (e) {
    if (e is DioException) {
      print('DioError: ${e.response?.statusCode}');
    } else {
      print(e);
    }
  }
}
