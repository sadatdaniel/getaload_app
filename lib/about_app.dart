// Settings, About this app: the app's version, and (on Android) updating it from the latest public release.
import 'package:flutter/material.dart';

import 'app_update.dart';
import 'jobs.dart' show fmtBytes;
import 'ui.dart';

class AboutApp extends StatefulWidget {
  const AboutApp({super.key});
  @override
  State<AboutApp> createState() => _AboutAppState();
}

class _AboutAppState extends State<AboutApp> {
  AppRelease? _latest;
  bool _checked = false, _busy = false;
  String _status = '';

  bool get _canUpdate => selfUpdate && isPhone;

  @override
  void initState() {
    super.initState();
    if (_canUpdate) _check(quiet: true);
  }

  Future<void> _check({bool quiet = false}) async {
    setState(() => _status = quiet ? '' : 'Checking…');
    try {
      final r = await latestRelease();
      if (mounted) {
        setState(() {
          _latest = r;
          _checked = true;
          _status = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = quiet ? '' : e.toString());
    }
  }

  Future<void> _update() async {
    final r = _latest!;
    final ok = await confirm(
      context,
      title: 'Update the app to ${r.version}?',
      body: SingleChildScrollView(
        child: Text(
          '${r.notes.trim().isEmpty ? '' : '${r.notes.trim()}\n\n'}'
          'Android asks once to allow updates from GetALoad, then shows "Update this app?". You stay signed in.',
        ),
      ),
      action: 'Download and update',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await installRelease(r, (done, total) {
        if (mounted) {
          setState(() => _status = total > 0 ? 'Downloading ${fmtBytes(done)} of ${fmtBytes(total)}' : 'Downloading…');
        }
      });
      if (mounted) setState(() => _status = 'Android is showing the update screen.');
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final newer = _latest != null && isNewer(_latest!.version, appVersion);
    final version = appVersion == 'dev' ? 'development build' : 'version $appVersion';
    return SettingsGroup(
      title: 'About this app',
      children: [
        SettingsRow(
          title: 'GetALoad',
          subtitle: _status.isNotEmpty
              ? _status
              : !_canUpdate
              ? 'App $version.'
              : newer
              ? 'App $version. Version ${_latest!.version} is available.'
              : _checked
              ? 'App $version. Up to date.'
              : 'App $version.',
          trailing: !_canUpdate
              ? null
              : _busy
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : newer
              ? TextButton(onPressed: _update, child: const Text('Update'))
              : IconButton(icon: const Icon(Icons.refresh), tooltip: 'Check for updates', onPressed: _check),
        ),
      ],
    );
  }
}
