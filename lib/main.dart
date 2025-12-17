import 'package:anpr/module/ANPR/anpr_bloc.dart';
import 'package:anpr/module/ANPR/anpr_page.dart';
import 'package:anpr/module/history/history_anpr_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AnprBloc>(create: (context) => AnprBloc()),
        BlocProvider<HistoryBloc>(create: (context) => HistoryBloc()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ANPR System',
        theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
        home: const AnprHomePage(),
      ),
    );
  }
}
