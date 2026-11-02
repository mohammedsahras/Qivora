import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/welcome/welcome_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/channels/channels_screen.dart';
import 'features/channels/channel_detail_screen.dart';
import 'features/status/status_screen.dart';
import 'features/chat/starred_messages_screen.dart';
import 'features/chat/archived_chats_screen.dart';
import 'features/groups/groups_screen.dart';
import 'features/groups/group_detail_screen.dart';
import 'features/communities/communities_screen.dart';
import 'features/communities/community_detail_screen.dart';
import 'features/home/home_screen.dart';
import 'features/chat/conversation_screen.dart';
import 'features/chat/message_search_screen.dart';
import 'features/contacts/contacts_screen.dart';
import 'features/call/calls_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/privacy_screen.dart';

final router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/forgot', builder: (_, __) => const ForgotPasswordScreen()),
    GoRoute(path: '/channels', builder: (_, __) => const ChannelsScreen()),
    GoRoute(path: '/channels/detail/:id', builder: (_, s) => ChannelDetailScreen(channelId: s.pathParameters['id']!)),
    GoRoute(path: '/status', builder: (_, __) => const StatusScreen()),
    GoRoute(path: '/starred', builder: (_, __) => const StarredMessagesScreen()),
    GoRoute(path: '/archived', builder: (_, __) => const ArchivedChatsScreen()),
    GoRoute(path: '/groups', builder: (_, __) => const GroupsScreen()),
    GoRoute(path: '/groups/detail/:id', builder: (_, s) => GroupDetailScreen(groupId: s.pathParameters['id']!)),
    GoRoute(path: '/communities', builder: (_, __) => const CommunitiesScreen()),
    GoRoute(path: '/communities/detail/:id', builder: (_, s) => CommunityDetailScreen(communityId: s.pathParameters['id']!)),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(
      path: '/chat/:id',
      builder: (_, s) => ConversationScreen(
        conversationId: s.pathParameters['id']!,
        conversationTitle: s.uri.queryParameters['title'] ?? 'Conversation',
      ),
    ),
    GoRoute(path: '/contacts', builder: (_, __) => const ContactsScreen()),
    GoRoute(path: '/search', builder: (_, __) => const MessageSearchScreen()),
    GoRoute(path: '/calls', builder: (_, __) => const CallsScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/privacy', builder: (_, __) => const PrivacyScreen()),
  ],
);

void main() {
  runApp(const ProviderScope(child: QivoraApp()));
}

class QivoraApp extends ConsumerWidget {
  const QivoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Theme selection from Settings is persisted in SharedPreferences via
    // [themeModeProvider] and applied here so light/dark/system take effect
    // immediately across the whole app.
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Qivora',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
