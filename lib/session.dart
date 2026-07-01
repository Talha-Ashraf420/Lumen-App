import 'xtream.dart';

/// The active session's client, exposed globally so the app-level player
/// overlay (which lives above the Navigator and has no widget context path to
/// the shell) can browse the catalog — e.g. the split-screen "watch alongside"
/// picker. Set by the login gate when the session client is created.
XtreamClient? activeClient;
