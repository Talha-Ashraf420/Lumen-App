import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../legal.dart';
import '../theme.dart';
import '../widgets.dart';

class LegalWelcomeScreen extends StatefulWidget {
  final Future<void> Function() onAccepted;
  const LegalWelcomeScreen({super.key, required this.onAccepted});

  @override
  State<LegalWelcomeScreen> createState() => _LegalWelcomeScreenState();
}

class _LegalWelcomeScreenState extends State<LegalWelcomeScreen> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    await widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Aurora(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Glass(
                    radius: 28,
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Center(child: Wordmark(size: 40)),
                        const SizedBox(height: 24),
                        const Text(
                          'Bring your own authorized media',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Lumen is an independent media player. It does not provide, sell, host, or endorse channels, subscriptions, playlists, or media.',
                          style: TextStyle(color: muted, height: 1.5),
                        ),
                        const SizedBox(height: 18),
                        const _Point(
                          icon: Icons.verified_user_outlined,
                          text:
                              'Use only sources you own or are authorized to access.',
                        ),
                        const _Point(
                          icon: Icons.lock_outline_rounded,
                          text:
                              'Android requires HTTPS sources and stores credentials in encrypted device storage.',
                        ),
                        const _Point(
                          icon: Icons.gavel_rounded,
                          text:
                              'You are responsible for the legality of your sources and the media you play or download.',
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LegalScreen(),
                            ),
                          ),
                          child: const Text('Read Legal & Privacy'),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _busy ? null : _accept,
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: bg,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _busy
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: bg,
                                    ),
                                  )
                                : const Text('I understand and agree'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  Future<void> _open(String value) async {
    await launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Legal & privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const _Section(
            title: 'Independent player',
            body:
                'Lumen is a media player and catalog client. Lumen does not provide, sell, host, curate, or endorse any subscription, channel, playlist, stream, or media. You must use only content you own or are legally authorized to access.',
          ),
          const _Section(
            title: 'Privacy on your device',
            body:
                'Provider credentials, saved profiles, favorites, watch progress, and download state are stored on your device. On Android and iOS, sensitive app data is kept in encrypted platform storage. Lumen sends requests only to services you configure and to optional metadata or subtitle services used by a feature. Lumen has no advertising or analytics SDK.',
          ),
          const _Section(
            title: 'Downloads',
            body:
                'Downloads are intended only for media you have permission to copy for offline use. Deleting a download removes its local file. Removing a profile deletes its saved credentials from this device.',
          ),
          const _Section(
            title: 'Third-party services',
            body:
                'This product uses the TMDB API but is not endorsed or certified by TMDB. Subtitle searches may use OpenSubtitles when that optional integration is configured. Those services have their own terms and privacy practices.',
          ),
          const _Section(
            title: 'Your responsibility',
            body:
                'You are responsible for your configured services, the rights to media you access, and compliance with applicable laws. Do not use Lumen to infringe copyright or bypass access controls.',
          ),
          const SizedBox(height: 8),
          _LinkTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy policy',
            subtitle: privacyPolicyUrl,
            onTap: () => _open(privacyPolicyUrl),
          ),
          const SizedBox(height: 10),
          _LinkTile(
            icon: Icons.movie_filter_outlined,
            title: 'The Movie Database',
            subtitle: 'themoviedb.org',
            onTap: () => _open('https://www.themoviedb.org'),
          ),
          const SizedBox(height: 10),
          _LinkTile(
            icon: Icons.email_outlined,
            title: 'Privacy & support contact',
            subtitle: supportEmail,
            onTap: () => _open('mailto:$supportEmail'),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Point({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(body, style: TextStyle(color: muted, height: 1.55)),
      ],
    ),
  );
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => RemoteTap(
    onTap: onTap,
    child: Glass(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: subtle, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.open_in_new_rounded, color: subtle, size: 18),
        ],
      ),
    ),
  );
}
