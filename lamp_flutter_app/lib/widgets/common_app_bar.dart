import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../screens/login_screen.dart';

class CommonAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final bool showLoginButton;
  final bool showHistoryIcon;
  final VoidCallback? onNewChat;
  final VoidCallback? onHistoryPressed;

  const CommonAppBar({
    super.key,
    required this.title,
    this.showLoginButton = false,
    this.showHistoryIcon = false,
    this.onNewChat,
    this.onHistoryPressed,
  });

  @override
  State<CommonAppBar> createState() => _CommonAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _CommonAppBarState extends State<CommonAppBar> {
  final AuthService _authService = AuthService();
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    if (widget.showLoginButton) {
      _checkLoginStatus();
    }
  }

  Future<void> _checkLoginStatus() async {
    final loggedIn = await _authService.isLoggedIn();
    if (mounted) {
      setState(() => _isLoggedIn = loggedIn);
    }
  }

  Future<void> _showLoginScreen() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
    if (result == true && mounted) {
      setState(() => _isLoggedIn = true);
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) {
      setState(() => _isLoggedIn = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged out successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(widget.title),
      // Add leading icon for drawer (History) if logged in and showHistoryIcon is true
      leading: widget.showHistoryIcon && _isLoggedIn
          ? IconButton(
              icon: const Icon(Icons.history),
              onPressed: widget.onHistoryPressed,
              tooltip: 'History',
            )
          : null,
      actions: widget.showLoginButton
          ? [
              // New Chat button (if logged in)
              if (_isLoggedIn)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: widget.onNewChat,
                  tooltip: 'New Chat',
                ),
              // Login/Logout button
              if (_isLoggedIn)
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: _logout,
                  tooltip: 'Logout',
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ElevatedButton(
                    onPressed: _showLoginScreen,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667EEA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text(
                      'Đăng nhập',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ]
          : null,
    );
  }
}
