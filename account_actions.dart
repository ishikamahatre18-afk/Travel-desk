import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/cloud_service.dart';
import '../widgets.dart';

/// The account dialogs the assistant can open. They need the owner's current
/// password, so these always go through a proper secure form, never the chat
/// text (which would put a password into the message list).
class AccountActions {
  /// Returns the new session, or null if nothing changed.
  static Future<Session?> changePassword(BuildContext context, Session session) async {
    final oldC = TextEditingController();
    final newC = TextEditingController();
    String? err;
    var busy = false;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Change password'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: oldC,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current password')),
            gap(10),
            TextField(
                controller: newC,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password')),
            if (err != null) ...[gap(10), NoticeCard(text: err!, error: true)],
          ]),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final problem = AccountService.passwordProblem(newC.text);
                      if (problem != null) {
                        setD(() => err = problem);
                        return;
                      }
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      final r = await AccountService.unlock(session.account, oldC.text);
                      if (r.status != UnlockStatus.ok) {
                        setD(() {
                          busy = false;
                          err = r.message;
                        });
                        return;
                      }
                      if (c.mounted) Navigator.pop(c, true);
                    },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    final newPw = newC.text;
    oldC.dispose();
    newC.dispose();
    if (changed != true) return null;

    final updated =
        await AccountService.rewrapPassword(session.account, session.dek, newPw);
    String? cloudNote;
    if (CloudService.configured && updated.cloudLinked) {
      final e = await CloudService.instance.changeCloudPassword(newPw);
      if (e != null) {
        cloudNote = ' The cloud login password could not be changed now ($e). '
            'Change it again when online.';
      }
    }
    CloudService.instance.updateAccount(updated, password: newPw);
    lastNote = 'Password changed.${cloudNote ?? ''}';
    return session.withAccount(updated, password: newPw);
  }

  /// A note for the chat to show after an action finishes.
  static String? lastNote;

  static Future<Session?> newRecoveryCode(BuildContext context, Session session) async {
    final c = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('New recovery code'),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Your current password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Continue')),
        ],
      ),
    );
    c.dispose();
    if (pw == null) return null;
    final r = await AccountService.unlock(session.account, pw);
    if (r.status != UnlockStatus.ok) {
      lastNote = r.message;
      return null;
    }
    final nr = await AccountService.newRecovery(session.account, session.dek);
    CloudService.instance.updateAccount(nr.account);
    final next = session.withAccount(nr.account);
    if (context.mounted) await showRecoveryCodeDialog(context, nr.code);
    lastNote = 'New recovery code created. The old one no longer works.';
    return next;
  }

  /// True if the owner confirmed. The caller locks and then removes.
  static Future<bool> confirmRemove(BuildContext context, Session session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove from this phone?'),
        content: Text(session.account.cloudLinked
            ? 'Your encrypted backup stays in the cloud. You can restore it any '
                'time with your email, password or recovery code.'
            : 'This account has NO cloud backup. Removing it deletes its data '
                'from this phone for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
        ],
      ),
    );
    return ok == true;
  }
}
