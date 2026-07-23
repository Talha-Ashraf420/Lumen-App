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
      backgroundColor: bg,
      body: Stack(
        children: [
          const Aurora(),
          SafeArea(
            child: Column(
              children: [
                EditorialPageHeader(
                  eyebrow: 'Trust centre',
                  title: 'Clear terms, private by design',
                  subtitle:
                      'Plain-language details about what Lumen does, stores and connects to.',
                  icon: Icons.shield_outlined,
                  onBack: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumn = constraints.maxWidth >= 820;
                      final contentWidth = constraints.maxWidth > 1120
                          ? 1120.0
                          : constraints.maxWidth;
                      final cardWidth = twoColumn
                          ? (contentWidth - 14) / 2
                          : double.infinity;
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1120),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Glass(
                                    radius: 26,
                                    tint: accent.withValues(
                                      alpha: isDark ? 0.13 : 0.08,
                                    ),
                                    padding: const EdgeInsets.all(24),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            color: accent,
                                            borderRadius: BorderRadius.circular(
                                              17,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.lock_person_outlined,
                                            color: onAccent,
                                            size: 25,
                                          ),
                                        ),
                                        const SizedBox(width: 17),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Your media. Your providers. Your responsibility.',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 19,
                                                  letterSpacing: -0.3,
                                                ),
                                              ),
                                              const SizedBox(height: 7),
                                              Text(
                                                'Lumen is an independent player—it supplies no content, runs no ads and includes no analytics SDK.',
                                                style: TextStyle(
                                                  color: muted,
                                                  height: 1.5,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  Text(
                                    'THE IMPORTANT PARTS',
                                    style: kSection(color: accentInk),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 14,
                                    runSpacing: 14,
                                    children: [
                                      _Section(
                                        width: cardWidth,
                                        index: '01',
                                        title: 'Independent player',
                                        body:
                                            'Lumen is a media player and catalog client. It does not provide, sell, host, curate, or endorse subscriptions, channels, playlists, streams, or media. Use only content you own or are authorized to access.',
                                      ),
                                      _Section(
                                        width: cardWidth,
                                        index: '02',
                                        title: 'Private on your device',
                                        body:
                                            'Profiles, favorites, progress and download state stay on your device. Sensitive mobile data uses encrypted platform storage. Lumen has no advertising or analytics SDK.',
                                      ),
                                      _Section(
                                        width: cardWidth,
                                        index: '03',
                                        title: 'Responsible downloads',
                                        body:
                                            'Download only media you have permission to copy. Deleting a download removes its local file; removing a profile removes its saved credentials from this device.',
                                      ),
                                      _Section(
                                        width: cardWidth,
                                        index: '04',
                                        title: 'Third-party services',
                                        body:
                                            'Metadata may come from TMDB and optional subtitle searches may use OpenSubtitles. Those independent services have their own terms and privacy practices.',
                                      ),
                                      _Section(
                                        width: cardWidth,
                                        index: '05',
                                        title: 'Your responsibility',
                                        body:
                                            'You are responsible for configured services, media rights and applicable laws. Do not use Lumen to infringe copyright or bypass access controls.',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'POLICIES & CONTACT',
                                    style: kSection(color: accentInk),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      SizedBox(
                                        width: twoColumn
                                            ? (contentWidth - 20) / 3
                                            : double.infinity,
                                        child: _LinkTile(
                                          icon: Icons.privacy_tip_outlined,
                                          title: 'Privacy policy',
                                          subtitle: privacyPolicyUrl,
                                          onTap: () => _open(privacyPolicyUrl),
                                        ),
                                      ),
                                      SizedBox(
                                        width: twoColumn
                                            ? (contentWidth - 20) / 3
                                            : double.infinity,
                                        child: _LinkTile(
                                          icon: Icons.movie_filter_outlined,
                                          title: 'The Movie Database',
                                          subtitle: 'themoviedb.org',
                                          onTap: () => _open(
                                            'https://www.themoviedb.org',
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: twoColumn
                                            ? (contentWidth - 20) / 3
                                            : double.infinity,
                                        child: _LinkTile(
                                          icon: Icons.email_outlined,
                                          title: 'Privacy & support',
                                          subtitle: supportEmail,
                                          onTap: () =>
                                              _open('mailto:$supportEmail'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
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
        Icon(icon, color: accentInk, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  final double width;
  final String index;
  final String title;
  final String body;
  const _Section({
    required this.width,
    required this.index,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Glass(
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                index,
                style: TextStyle(
                  color: accentInk,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: TextStyle(color: muted, height: 1.5, fontSize: 13)),
        ],
      ),
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
          Icon(icon, color: accentInk),
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
