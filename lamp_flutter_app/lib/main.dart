import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/voice_chat_screen.dart';
import 'screens/text_chat_screen.dart';
import 'screens/translate_screen.dart';
import 'providers/auth_provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const LampApp(),
    ),
  );
}

class LampApp extends StatelessWidget {
  const LampApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lamp AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1B1E),
        primaryColor: const Color(0xFF667EEA),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF667EEA),
          secondary: const Color(0xFF764BA2),
          surface: const Color(0xFF2D2F33),
          background: const Color(0xFF1A1B1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2D2F33),
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          VoiceChatScreen(),
          TextChatScreen(),
          TranslateScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF2D2F33),
        selectedItemColor: const Color(0xFF667EEA),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.mic),
            label: 'Voice',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Text',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.translate),
            label: 'Translate',
          ),
        ],
      ),
    );
  }
}
