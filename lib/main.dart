import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vehicle_identification_number/module/home/home_page.dart';
import 'package:vehicle_identification_number/module/plat%20capture/plat_capture_bloc.dart';
import 'package:vehicle_identification_number/module/plat%20gallery/plat_gallery_bloc.dart';
import 'package:vehicle_identification_number/module/plat%20gallery/plat_gallery_page.dart';
import 'package:vehicle_identification_number/module/plat%20realtime/plat_realtime_bloc.dart';
import 'package:vehicle_identification_number/module/zoom%20feature%20dengan%20enchange/plat_capture_zoom_bloc.dart';
import 'package:vehicle_identification_number/module/zoom%20feature%20dengan%20enchange/plat_capture_zoom_page.dart';
import 'package:vehicle_identification_number/service/ocr_isolate_pool.dart';
import 'package:vehicle_identification_number/service/yolo_isolate_pool.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('plates');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final modelBytes = await rootBundle.load(
    'assets/models/license_plate_detector_float16.tflite',
  );
  final bytes = modelBytes.buffer.asUint8List();

  final yoloPool = YoloIsolatePool();
  await yoloPool.init(bytes, 640, 0.5);

  final ocrPool = OcrIsolatePool();
  ocrPool.start();

  runApp(MyApp(yoloPool: yoloPool, ocrPool: ocrPool));
}

class MyApp extends StatelessWidget {
  final YoloIsolatePool yoloPool;
  final OcrIsolatePool ocrPool;

  const MyApp({super.key, required this.yoloPool, required this.ocrPool});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (BuildContext context) =>
              PlateRealtimeBloc(yoloPool: yoloPool, ocrPool: ocrPool),
        ),
        BlocProvider(
          create: (BuildContext context) =>
              PlateCameraCaptureBloc(yolo: yoloPool, ocr: ocrPool),
        ),
        BlocProvider(
          create: (_) => PlateGalleryBloc(yolo: yoloPool, ocr: ocrPool),
          child: const PlateGalleryPage(),
        ),
        BlocProvider(
          create: (_) =>
              PlateCameraCaptureZoomBloc(yolo: yoloPool, ocr: ocrPool),
          child: const PlateCameraCaptureZoomPage(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Plat License Scanner',
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0E1621),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
        home: const HomePage(),
      ),
    );
  }
}
