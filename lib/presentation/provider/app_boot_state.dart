import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_boot_state.g.dart';

/// Whether the work that has to finish before the timeline is shown is done.
///
/// The router builds its first route behind the boot gate, so a session
/// created there would resolve its server id before the server list exists.
/// [InitialDirectorPage] waits on this instead.
@Riverpod(keepAlive: true)
class AppBootState extends _$AppBootState {
  @override
  bool build() => false;

  void complete() => state = true;
}
